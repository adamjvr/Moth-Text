// SPDX-License-Identifier: MPL-2.0
//
// Moth-owned convenience wrapper around Luna's product-neutral shaped-text
// painter. Font selection, shaping, glyph caching, and rasterization remain Luna
// responsibilities; Moth chooses where product text appears.

import LunaRender
import LunaTextRender
import LunaUI

enum MothUnicodeTextPainter {
    private static let renderer: LunaUnicodeTextRenderer? = {
        try? LunaUnicodeTextRenderer(monospacedPointSize: 10)
    }()

    private static let shapedCellAdvance: Int = {
        guard let renderer, let layout = try? renderer.layout("M") else { return 6 }
        return max(1, layout.advancePixels)
    }()

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
        if let renderer {
            do {
                _ = try renderer.draw(
                    text,
                    atX: x,
                    baselineY: y + 10,
                    color: color,
                    maximumWidth: maximumWidth,
                    into: &framebuffer
                )
                return
            } catch {
                // The explicit diagnostic fallback keeps application bring-up
                // usable even when a development machine lacks a loadable font.
            }
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
