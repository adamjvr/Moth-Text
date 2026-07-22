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
            _ = try activeRenderer.draw(
                text,
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
