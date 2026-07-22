// SPDX-License-Identifier: MPL-2.0
//
// MothPaneEditorSurface.swift
//
// Moth-owned projection of one editor view into Luna's reusable pane-bound,
// soft-wrapped text surface. Luna owns geometry, clipping, wrapping, hit testing,
// shaping, glyph rasterization, and accessibility coordinates. Moth owns the
// document and per-view state.

import LunaCore
import LunaRender
import LunaTheme
import LunaUI
import MothEditor

struct MothPaneEditorSurface {
    let paneID: LunaPaneID
    let contentFrame: LunaPaneContentFrame
    let textView: LunaStaticTextView

    init(
        paneID: LunaPaneID,
        contentFrame: LunaPaneContentFrame,
        viewState: MothEditorViewState,
        snapshot: LunaTextStorageSnapshot,
        isActive: Bool
    ) {
        let presentation = MothLunaViewProjection.presentation(
            for: viewState,
            snapshot: snapshot
        )

        self.paneID = paneID
        self.contentFrame = contentFrame
        self.textView = LunaStaticTextView(
            id: contentFrame.nodeID.child("text-view"),
            bounds: contentFrame.contentBounds,
            document: snapshot.staticDocument,
            scrollTopLine: viewState.viewport.firstVisibleLine,
            scrollTopVisualRow: viewState.viewport.firstVisibleVisualRow,
            currentLineIndex: presentation.caret.location.lineIndex,
            theme: MothApplicationTheme.theme,
            metrics: MothUnicodeTextPainter.editorMetrics,
            wrapMode: .soft,
            geometryProvider: MothUnicodeTextPainter.geometryProvider,
            isFocused: isActive,
            isEditable: true,
            caret: isActive ? presentation.caret : nil,
            selection: presentation.selection
        )
    }

    func draw(into framebuffer: inout LunaFramebuffer) {
        let layout = textView.layout()
        let theme = textView.theme
        let style = LunaEditorVisualStyle(theme: theme)

        framebuffer.fillRect(textView.bounds, color: style.background)

        if !layout.gutterBounds.isEmpty {
            framebuffer.fillRect(layout.gutterBounds, color: style.gutterBackground)
        }
        if !layout.scrollbarLaneBounds.isEmpty {
            framebuffer.fillRect(layout.scrollbarLaneBounds, color: style.scrollbarTrack)
        }

        for line in layout.visibleLines where line.isCurrentLine {
            framebuffer.fillRect(line.rowBounds, color: style.currentLineBackground)
        }
        for highlight in layout.highlightRects {
            framebuffer.fillRect(
                highlight.selectionRect.bounds,
                color: highlight.color.asRenderColor
            )
        }
        for selection in layout.selectionRects {
            framebuffer.fillRect(selection.bounds, color: style.selectionBackground)
        }
        if layout.gutterBounds.w > 0 {
            framebuffer.fillRect(
                LunaRectI(
                    x: layout.gutterBounds.x + layout.gutterBounds.w - 1,
                    y: layout.gutterBounds.y,
                    w: 1,
                    h: layout.gutterBounds.h
                ),
                color: theme.ui.chrome.separator.asRenderColor
            )
        }

        for visible in layout.visibleLines {
            let textY = visible.rowBounds.y + max(0, (visible.rowBounds.h - 10) / 2)
            if !visible.lineNumberText.isEmpty {
                MothUnicodeTextPainter.draw(
                    visible.lineNumberText,
                    atX: visible.lineNumberBounds.x,
                    y: textY,
                    color: style.gutterForeground,
                    maximumWidth: visible.lineNumberBounds.w,
                    into: &framebuffer
                )
            }
            MothUnicodeTextPainter.draw(
                visible.rowGeometry,
                atX: visible.textBounds.x,
                y: textY,
                color: style.foreground,
                maximumWidth: visible.textBounds.w,
                into: &framebuffer
            )
        }

        if let thumb = layout.scrollbarThumbBounds {
            framebuffer.fillRect(thumb, color: style.scrollbarThumb)
        }

        // Caret is intentionally painted after glyphs. Its absolute X coordinate
        // comes from the same shaped row geometry that painted the text.
        if let caret = layout.caretRect {
            framebuffer.fillRect(caret, color: style.caret)
        }

        if textView.isFocused {
            let focus = theme.ui.textField.focusedBorder.asRenderColor
            let bounds = textView.bounds
            framebuffer.fillRect(LunaRectI(x: bounds.x, y: bounds.y, w: bounds.w, h: 1), color: focus)
            framebuffer.fillRect(LunaRectI(x: bounds.x, y: bounds.y + bounds.h - 1, w: bounds.w, h: 1), color: focus)
            framebuffer.fillRect(LunaRectI(x: bounds.x, y: bounds.y, w: 1, h: bounds.h), color: focus)
            framebuffer.fillRect(LunaRectI(x: bounds.x + bounds.w - 1, y: bounds.y, w: 1, h: bounds.h), color: focus)
        }
    }
}
