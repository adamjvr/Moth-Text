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

    private static let maximumCacheEntryCount = 256
    private static let maximumCacheCost = 2 * 1024 * 1024
    private var expandedRunCache: [MothExpandedTextCacheKey: MothExpandedTextRun] = [:]
    private var expandedRunCacheOrder: [MothExpandedTextCacheKey] = []
    private var expandedRunCacheCost = 0
    private var layoutCache: [String: LunaUnicodeTextLayout] = [:]
    private var layoutCacheOrder: [String] = []
    private var layoutCacheCost = 0

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
        if let cached = layoutCache[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let layout = try activeRenderer.layout(text)
        let cost = text.utf8.count
            + layout.glyphs.count * MemoryLayout<LunaUnicodeGlyphPlacement>.stride
            + layout.insertionPositions.count * MemoryLayout<LunaUnicodeTextInsertionPosition>.stride
        guard cost <= Self.maximumCacheCost else { return layout }

        lock.lock()
        if renderer === activeRenderer, layoutCache[text] == nil {
            layoutCache[text] = layout
            layoutCacheOrder.append(text)
            layoutCacheCost += cost
            trimLayoutCache()
        }
        let result = layoutCache[text] ?? layout
        lock.unlock()
        return result
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

    private func trimLayoutCache() {
        while layoutCache.count > Self.maximumCacheEntryCount
            || layoutCacheCost > Self.maximumCacheCost {
            guard !layoutCacheOrder.isEmpty else { break }
            let text = layoutCacheOrder.removeFirst()
            guard let removed = layoutCache.removeValue(forKey: text) else { continue }
            layoutCacheCost -= text.utf8.count
                + removed.glyphs.count * MemoryLayout<LunaUnicodeGlyphPlacement>.stride
                + removed.insertionPositions.count * MemoryLayout<LunaUnicodeTextInsertionPosition>.stride
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
        layoutCacheOrder.removeAll(keepingCapacity: false)
        layoutCacheCost = 0
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
