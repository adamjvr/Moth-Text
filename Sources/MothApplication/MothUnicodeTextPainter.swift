// SPDX-License-Identifier: MPL-2.0
//
// Moth-owned convenience wrapper around Luna's product-neutral shaped-text
// painter. Font selection, shaping, glyph caching, and rasterization remain Luna
// responsibilities; Moth chooses where product text appears and reports when the
// application has entered the diagnostic ASCII fallback path.

import Foundation
import LunaRender
import LunaTextRender
import LunaUI

public struct MothUnicodeTextDiagnostics: Hashable, Sendable {
    public enum Mode: String, Hashable, Sendable {
        case unicode
        case diagnosticFallback
    }

    public let mode: Mode
    public let fontPath: String?
    public let pointSize: Double
    public let failureDescription: String?

    public var isUsingFallback: Bool { mode == .diagnosticFallback }

    public var warningMessage: String? {
        isUsingFallback ? "TEXT FALLBACK: Unicode renderer unavailable" : nil
    }

    public func prependingWarning(to status: String) -> String {
        guard let warningMessage else { return status }
        return "\(warningMessage)   \(status)"
    }
}

public struct MothUnicodeTextPerformanceSnapshot: Hashable, Sendable {
    public let layoutRequestCount: UInt64
    public let layoutCacheHitCount: UInt64
    public let layoutCacheMissCount: UInt64
    public let shapingNanoseconds: UInt64
    public let layoutCacheEntryCount: Int
    public let layoutCacheCost: Int
    public let layoutCacheEvictionCount: UInt64

    public var cacheHitRate: Double {
        guard layoutRequestCount > 0 else { return 0 }
        return Double(layoutCacheHitCount) / Double(layoutRequestCount)
    }

    public var shapingMilliseconds: Double {
        Double(shapingNanoseconds) / 1_000_000.0
    }

    public var compactStatusText: String {
        "shape H\(layoutCacheHitCount)/M\(layoutCacheMissCount) E\(layoutCacheEvictionCount) "
            + String(format: "%.2fms", shapingMilliseconds)
    }
}

private struct MothExpandedTextRun: Sendable {
    struct Boundary: Sendable {
        var sourceUTF8Offset: Int
        var renderedUTF8Offset: Int
    }

    var renderedText: String
    var boundaries: [Boundary]

    static func expandingTabs(
        in sourceText: String,
        tabWidth: Int = 4,
        startingVisualColumn: Int = 0
    ) -> MothExpandedTextRun {
        let width = max(1, tabWidth)
        var rendered = ""
        rendered.reserveCapacity(sourceText.count)
        var sourceOffset = 0
        var renderedOffset = 0
        var renderedColumn = max(0, startingVisualColumn)
        var boundaries = [
            Boundary(
                sourceUTF8Offset: 0,
                renderedUTF8Offset: 0
            ),
        ]

        for character in sourceText {
            let sourceLength = String(character).utf8.count
            let replacement: String
            if character == "\t" {
                let spaceCount = width - (renderedColumn % width)
                replacement = String(repeating: " ", count: spaceCount)
                renderedColumn += spaceCount
            } else {
                replacement = String(character)
                renderedColumn += 1
            }
            rendered.append(replacement)
            sourceOffset += sourceLength
            renderedOffset += replacement.utf8.count
            boundaries.append(
                Boundary(
                    sourceUTF8Offset: sourceOffset,
                    renderedUTF8Offset: renderedOffset
                )
            )
        }

        return MothExpandedTextRun(
            renderedText: rendered,
            boundaries: boundaries
        )
    }

    func slice(sourceUTF8Range requestedRange: Range<Int>) -> MothExpandedTextRun {
        let sourceLength = boundaries.last?.sourceUTF8Offset ?? 0
        let lower = min(max(0, requestedRange.lowerBound), sourceLength)
        let upper = min(max(lower, requestedRange.upperBound), sourceLength)
        let lowerIndex = boundaryIndex(atOrBefore: lower)
        let upperIndex = boundaryIndex(atOrBefore: upper)
        let lowerBoundary = boundaries[lowerIndex]
        let upperBoundary = boundaries[upperIndex]

        let lowerUTF8 = renderedText.utf8.index(
            renderedText.utf8.startIndex,
            offsetBy: lowerBoundary.renderedUTF8Offset
        )
        let upperUTF8 = renderedText.utf8.index(
            renderedText.utf8.startIndex,
            offsetBy: upperBoundary.renderedUTF8Offset
        )
        let lowerString = String.Index(lowerUTF8, within: renderedText)
            ?? renderedText.startIndex
        let upperString = String.Index(upperUTF8, within: renderedText)
            ?? renderedText.endIndex
        let slicedText = String(renderedText[lowerString..<upperString])
        let slicedBoundaries = boundaries[lowerIndex...upperIndex].map { boundary in
            Boundary(
                sourceUTF8Offset: boundary.sourceUTF8Offset - lowerBoundary.sourceUTF8Offset,
                renderedUTF8Offset: boundary.renderedUTF8Offset - lowerBoundary.renderedUTF8Offset
            )
        }
        return MothExpandedTextRun(
            renderedText: slicedText,
            boundaries: Array(slicedBoundaries)
        )
    }

    private func boundaryIndex(atOrBefore requestedOffset: Int) -> Int {
        var low = 0
        var high = boundaries.count
        while low < high {
            let middle = (low + high) / 2
            if boundaries[middle].sourceUTF8Offset <= requestedOffset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return max(0, low - 1)
    }
}

private struct MothExpandedTextCacheKey: Hashable, Sendable {
    var sourceText: String
    var tabWidth: Int
}

struct MothUnicodeTextGeometryProvider: LunaStaticTextGeometryProvider, Sendable {
    func geometry(for request: LunaStaticTextGeometryRequest) -> LunaStaticTextRowGeometry {
        MothUnicodeTextPainter.geometry(for: request)
    }
}

final class MothUnicodeTextRendererState: @unchecked Sendable {
    typealias RendererFactory = (Double) throws -> LunaUnicodeTextRenderer
    typealias Logger = (String) -> Void

    private let lock = NSLock()
    private let pointSize: Double
    private let logger: Logger
    private var renderer: LunaUnicodeTextRenderer?
    private var fontPath: String?
    private var failureDescription: String?
    private var didLogFailure: Bool

    private static let maximumCacheEntryCount = 128
    private static let maximumCacheCost = 2 * 1024 * 1024
    private var expandedRunCache: [MothExpandedTextCacheKey: MothExpandedTextRun] = [:]
    private var expandedRunCacheOrder: [MothExpandedTextCacheKey] = []
    private var expandedRunCacheCost = 0
    private struct LayoutCacheEntry {
        var layout: LunaUnicodeTextLayout
        var cost: Int
        var lastAccessGeneration: UInt64
    }

    private var layoutCache: [String: LayoutCacheEntry] = [:]
    private var layoutCacheCost = 0
    private var layoutAccessGeneration: UInt64 = 0
    private var layoutCacheEvictionCount: UInt64 = 0
    private var layoutRequestCount: UInt64 = 0
    private var layoutCacheHitCount: UInt64 = 0
    private var layoutCacheMissCount: UInt64 = 0
    private var shapingNanoseconds: UInt64 = 0

    init(
        pointSize: Double = 10,
        rendererFactory: RendererFactory = { pointSize in
            try LunaUnicodeTextRenderer(monospacedPointSize: pointSize)
        },
        logger: @escaping Logger = MothUnicodeTextRendererState.writeDiagnostic
    ) {
        self.pointSize = pointSize
        self.logger = logger

        do {
            let renderer = try rendererFactory(pointSize)
            self.renderer = renderer
            self.fontPath = renderer.font.filePath
            self.failureDescription = nil
            self.didLogFailure = false
        } catch {
            let description = String(describing: error)
            self.renderer = nil
            self.fontPath = nil
            self.failureDescription = description
            self.didLogFailure = true
            logger(Self.logMessage(for: description))
        }
    }

    var diagnostics: MothUnicodeTextDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        return MothUnicodeTextDiagnostics(
            mode: renderer == nil ? .diagnosticFallback : .unicode,
            fontPath: fontPath,
            pointSize: pointSize,
            failureDescription: failureDescription
        )
    }

    var performanceSnapshot: MothUnicodeTextPerformanceSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return MothUnicodeTextPerformanceSnapshot(
            layoutRequestCount: layoutRequestCount,
            layoutCacheHitCount: layoutCacheHitCount,
            layoutCacheMissCount: layoutCacheMissCount,
            shapingNanoseconds: shapingNanoseconds,
            layoutCacheEntryCount: layoutCache.count,
            layoutCacheCost: layoutCacheCost,
            layoutCacheEvictionCount: layoutCacheEvictionCount
        )
    }

    func resetPerformanceCounters() {
        lock.lock()
        layoutRequestCount = 0
        layoutCacheHitCount = 0
        layoutCacheMissCount = 0
        shapingNanoseconds = 0
        layoutCacheEvictionCount = 0
        lock.unlock()
    }

    func monospacedAdvance(fallback: Int) -> Int {
        guard let activeRenderer = currentRenderer() else { return max(1, fallback) }
        do {
            return max(1, try activeRenderer.layout("M").advancePixels)
        } catch {
            transitionToFallback(after: error)
            return max(1, fallback)
        }
    }

    func geometry(
        for request: LunaStaticTextGeometryRequest,
        fallbackAdvance: Int,
        tabWidth: Int = 4
    ) -> LunaStaticTextRowGeometry {
        let expandedLine = expandedRun(
            for: request.completeLineText,
            tabWidth: tabWidth
        )
        let expanded = expandedLine.slice(sourceUTF8Range: request.utf8Range)
        let sourceText = request.sourceText

        guard let activeRenderer = currentRenderer() else {
            return fallbackGeometry(
                sourceText: sourceText,
                expanded: expanded,
                advance: fallbackAdvance
            )
        }

        do {
            let layout = try cachedLayout(
                for: expanded.renderedText,
                renderer: activeRenderer
            )
            let positions = expanded.boundaries.map { boundary in
                LunaStaticTextInsertionPosition(
                    utf8Offset: boundary.sourceUTF8Offset,
                    x26Dot6: layout.insertionX26Dot6(
                        forUTF8Offset: boundary.renderedUTF8Offset
                    )
                )
            }
            return LunaStaticTextRowGeometry(
                sourceText: sourceText,
                renderedText: expanded.renderedText,
                insertionPositions: positions,
                advance26Dot6: layout.advance26Dot6
            )
        } catch {
            transitionToFallback(after: error)
            return fallbackGeometry(
                sourceText: sourceText,
                expanded: expanded,
                advance: fallbackAdvance
            )
        }
    }

    func draw(
        _ geometry: LunaStaticTextRowGeometry,
        atX x: Int,
        baselineY: Int,
        color: LunaRGBA8,
        maximumWidth: Int?,
        into framebuffer: inout LunaFramebuffer
    ) -> Bool {
        guard let activeRenderer = currentRenderer() else { return false }
        do {
            let layout = try cachedLayout(
                for: geometry.renderedText,
                renderer: activeRenderer
            )
            try activeRenderer.draw(
                layout,
                atX: x,
                baselineY: baselineY,
                color: color,
                maximumWidth: maximumWidth,
                into: &framebuffer
            )
            return true
        } catch {
            transitionToFallback(after: error)
            return false
        }
    }

    func draw(
        _ text: String,
        atX x: Int,
        baselineY: Int,
        color: LunaRGBA8,
        maximumWidth: Int?,
        into framebuffer: inout LunaFramebuffer
    ) -> Bool {
        guard let activeRenderer = currentRenderer() else { return false }

        do {
            let layout = try cachedLayout(for: text, renderer: activeRenderer)
            try activeRenderer.draw(
                layout,
                atX: x,
                baselineY: baselineY,
                color: color,
                maximumWidth: maximumWidth,
                into: &framebuffer
            )
            return true
        } catch {
            transitionToFallback(after: error)
            return false
        }
    }

    private func expandedRun(
        for sourceText: String,
        tabWidth: Int
    ) -> MothExpandedTextRun {
        let key = MothExpandedTextCacheKey(
            sourceText: sourceText,
            tabWidth: max(1, tabWidth)
        )

        lock.lock()
        if let cached = expandedRunCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let expanded = MothExpandedTextRun.expandingTabs(
            in: sourceText,
            tabWidth: key.tabWidth
        )
        let cost = sourceText.utf8.count
            + expanded.renderedText.utf8.count
            + expanded.boundaries.count * MemoryLayout<MothExpandedTextRun.Boundary>.stride
        guard cost <= Self.maximumCacheCost else { return expanded }

        lock.lock()
        if expandedRunCache[key] == nil {
            expandedRunCache[key] = expanded
            expandedRunCacheOrder.append(key)
            expandedRunCacheCost += cost
            trimExpandedRunCache()
        }
        let result = expandedRunCache[key] ?? expanded
        lock.unlock()
        return result
    }

    private func cachedLayout(
        for text: String,
        renderer activeRenderer: LunaUnicodeTextRenderer
    ) throws -> LunaUnicodeTextLayout {
        lock.lock()
        layoutRequestCount &+= 1
        layoutAccessGeneration &+= 1
        let accessGeneration = layoutAccessGeneration
        if var cached = layoutCache[text] {
            layoutCacheHitCount &+= 1
            cached.lastAccessGeneration = accessGeneration
            layoutCache[text] = cached
            lock.unlock()
            return cached.layout
        }
        layoutCacheMissCount &+= 1
        lock.unlock()

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let layout = try activeRenderer.layout(text)
        let finishedAt = DispatchTime.now().uptimeNanoseconds
        let shapeDuration = finishedAt >= startedAt ? finishedAt - startedAt : 0
        let cost = Self.layoutCacheCost(for: text, layout: layout)

        lock.lock()
        shapingNanoseconds &+= shapeDuration
        guard cost <= Self.maximumCacheCost else {
            lock.unlock()
            return layout
        }

        // Another caller may have populated the same key while shaping occurred.
        // Reuse that canonical entry and update its generation rather than
        // replacing it or double-counting its cost.
        if var existing = layoutCache[text] {
            existing.lastAccessGeneration = max(
                existing.lastAccessGeneration,
                accessGeneration
            )
            layoutCache[text] = existing
            let result = existing.layout
            lock.unlock()
            return result
        }

        guard renderer === activeRenderer else {
            lock.unlock()
            return layout
        }

        layoutCache[text] = LayoutCacheEntry(
            layout: layout,
            cost: cost,
            lastAccessGeneration: accessGeneration
        )
        layoutCacheCost += cost
        trimLayoutCacheAfterInsertion()
        let result = layoutCache[text]?.layout ?? layout
        lock.unlock()
        return result
    }

    private static func layoutCacheCost(
        for text: String,
        layout: LunaUnicodeTextLayout
    ) -> Int {
        text.utf8.count
            + layout.glyphs.count * MemoryLayout<LunaUnicodeGlyphPlacement>.stride
            + layout.insertionPositions.count * MemoryLayout<LunaUnicodeTextInsertionPosition>.stride
    }

    private func trimExpandedRunCache() {
        while expandedRunCache.count > Self.maximumCacheEntryCount
            || expandedRunCacheCost > Self.maximumCacheCost {
            guard !expandedRunCacheOrder.isEmpty else { break }
            let key = expandedRunCacheOrder.removeFirst()
            guard let removed = expandedRunCache.removeValue(forKey: key) else { continue }
            expandedRunCacheCost -= key.sourceText.utf8.count
                + removed.renderedText.utf8.count
                + removed.boundaries.count * MemoryLayout<MothExpandedTextRun.Boundary>.stride
        }
    }

    /// Eviction is intentionally confined to insertion/maintenance. Cache hits
    /// remain dictionary lookup plus one generation update; they never scan or
    /// shift an ordering array on the editor's render hot path.
    private func trimLayoutCacheAfterInsertion() {
        while layoutCache.count > Self.maximumCacheEntryCount
            || layoutCacheCost > Self.maximumCacheCost {
            guard let victim = layoutCache.min(
                by: { lhs, rhs in
                    if lhs.value.lastAccessGeneration == rhs.value.lastAccessGeneration {
                        return lhs.key < rhs.key
                    }
                    return lhs.value.lastAccessGeneration < rhs.value.lastAccessGeneration
                }
            ) else { break }
            guard let removed = layoutCache.removeValue(forKey: victim.key) else { continue }
            layoutCacheCost -= removed.cost
            layoutCacheEvictionCount &+= 1
        }
    }

    private func fallbackGeometry(
        sourceText: String,
        expanded: MothExpandedTextRun,
        advance: Int
    ) -> LunaStaticTextRowGeometry {
        let cellAdvance = max(1, advance)
        let positions = expanded.boundaries.map { boundary in
            let utf8End = expanded.renderedText.utf8.index(
                expanded.renderedText.utf8.startIndex,
                offsetBy: boundary.renderedUTF8Offset
            )
            let prefixEnd = String.Index(utf8End, within: expanded.renderedText)
                ?? expanded.renderedText.endIndex
            let characterCount = expanded.renderedText[..<prefixEnd].count
            return LunaStaticTextInsertionPosition(
                utf8Offset: boundary.sourceUTF8Offset,
                x26Dot6: Int32(characterCount * cellAdvance * 64)
            )
        }
        return LunaStaticTextRowGeometry(
            sourceText: sourceText,
            renderedText: expanded.renderedText,
            insertionPositions: positions,
            advance26Dot6: positions.last?.x26Dot6 ?? 0
        )
    }

    private func currentRenderer() -> LunaUnicodeTextRenderer? {
        lock.lock()
        defer { lock.unlock() }
        return renderer
    }

    private func transitionToFallback(after error: Error) {
        let description = String(describing: error)
        var messageToLog: String?

        lock.lock()
        renderer = nil
        expandedRunCache.removeAll(keepingCapacity: false)
        expandedRunCacheOrder.removeAll(keepingCapacity: false)
        expandedRunCacheCost = 0
        layoutCache.removeAll(keepingCapacity: false)
        layoutCacheCost = 0
        layoutAccessGeneration = 0
        if failureDescription == nil {
            failureDescription = description
        }
        if !didLogFailure {
            didLogFailure = true
            messageToLog = Self.logMessage(for: description)
        }
        lock.unlock()

        if let messageToLog {
            logger(messageToLog)
        }
    }

    private static func logMessage(for description: String) -> String {
        "[MothText] Unicode renderer unavailable; diagnostic fallback active: \(description)"
    }

    private static func writeDiagnostic(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

enum MothUnicodeTextPainter {
    private static let state = MothUnicodeTextRendererState()

    static let geometryProvider = MothUnicodeTextGeometryProvider()
    static var diagnostics: MothUnicodeTextDiagnostics { state.diagnostics }
    static var performanceSnapshot: MothUnicodeTextPerformanceSnapshot {
        state.performanceSnapshot
    }

    static func resetPerformanceCountersForTesting() {
        state.resetPerformanceCounters()
    }

    private static let shapedCellAdvance = state.monospacedAdvance(fallback: 6)

    static let editorMetrics: LunaStaticTextViewMetrics = {
        var metrics = LunaStaticTextViewMetrics.demo
        metrics.glyphMetrics = LunaDebugTextMetrics(
            glyphWidth: max(1, shapedCellAdvance - 1),
            glyphHeight: 10,
            advance: shapedCellAdvance,
            lineHeight: 14
        )
        metrics.lineHeight = 14
        return metrics
    }()

    static func geometry(
        for request: LunaStaticTextGeometryRequest
    ) -> LunaStaticTextRowGeometry {
        state.geometry(
            for: request,
            fallbackAdvance: LunaDebugBitmapTextRenderer.advance
        )
    }

    static func geometry(for sourceText: String) -> LunaStaticTextRowGeometry {
        geometry(for: LunaStaticTextGeometryRequest(sourceText: sourceText))
    }

    static func draw(
        _ geometry: LunaStaticTextRowGeometry,
        atX x: Int,
        y: Int,
        color: LunaRGBA8,
        maximumWidth: Int? = nil,
        into framebuffer: inout LunaFramebuffer
    ) {
        if state.draw(
            geometry,
            atX: x,
            baselineY: y + 10,
            color: color,
            maximumWidth: maximumWidth,
            into: &framebuffer
        ) {
            return
        }

        LunaDebugBitmapTextRenderer.draw(
            asciiVisibleFallback(for: geometry.renderedText),
            atX: x,
            y: y,
            color: color,
            maximumWidth: maximumWidth,
            into: &framebuffer
        )
    }

    static func draw(
        _ text: String,
        atX x: Int,
        y: Int,
        color: LunaRGBA8,
        maximumWidth: Int? = nil,
        into framebuffer: inout LunaFramebuffer
    ) {
        if state.draw(
            text,
            atX: x,
            baselineY: y + 10,
            color: color,
            maximumWidth: maximumWidth,
            into: &framebuffer
        ) {
            return
        }

        LunaDebugBitmapTextRenderer.draw(
            asciiVisibleFallback(for: text),
            atX: x,
            y: y,
            color: color,
            maximumWidth: maximumWidth,
            into: &framebuffer
        )
    }

    private static func asciiVisibleFallback(for text: String) -> String {
        String(text.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            if value >= 32 && value <= 126 {
                return Character(String(scalar))
            }
            return "?"
        })
    }
}
