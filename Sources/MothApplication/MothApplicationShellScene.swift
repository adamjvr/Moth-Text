// SPDX-License-Identifier: MPL-2.0
//
// MothApplicationShellScene.swift
//
// First Luna-rendered Moth editor slice backed by a real Moth-owned source
// buffer. The scene remains platform-neutral: Luna owns the native host and
// normalized input stream, while Moth owns text, transactions, revisions,
// dirty-state policy, and independent editor views.

import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaUI
import MothEditor
import MothTextCore

public struct MothApplicationShellScene: Sendable {
    public private(set) var framebufferSize: LunaSizeI
    public private(set) var pointerAccentIsActive: Bool
    public private(set) var keyboardEventCount: UInt64

    public let buffer: MothInMemorySourceBuffer
    public private(set) var primaryView: MothEditorViewState
    public private(set) var secondaryView: MothEditorViewState

    public init(
        initialSize: LunaSizeI = LunaSizeI(width: 1100, height: 720),
        initialText: String = Self.demoText
    ) {
        self.framebufferSize = initialSize
        self.pointerAccentIsActive = false
        self.keyboardEventCount = 0

        let buffer = MothInMemorySourceBuffer(text: initialText)
        self.buffer = buffer
        self.primaryView = MothEditorViewState(
            bufferID: buffer.id,
            caret: .zero,
            viewport: MothEditorViewportState(firstVisibleLine: 0)
        )
        self.secondaryView = MothEditorViewState(
            bufferID: buffer.id,
            caret: MothTextOffset(rawValue: initialText.utf8.count),
            preferredUTF8Column: 12,
            viewport: MothEditorViewportState(firstVisibleLine: 2)
        )

        let snapshot = buffer.snapshot()
        _ = self.primaryView.synchronize(with: snapshot)
        _ = self.secondaryView.synchronize(with: snapshot)
    }

    public var wantsContinuousRendering: Bool { false }
    public var bufferSnapshot: MothSourceBufferSnapshot { buffer.snapshot() }

    public mutating func handleHostEvent(
        _ event: LunaHostInputEvent,
        framebufferSize: LunaSizeI
    ) -> LunaFrameInvalidationSet {
        self.framebufferSize = framebufferSize

        switch event {
        case .quit:
            return LunaFrameInvalidationSet()

        case .windowResized:
            return LunaFrameInvalidationSet(.windowResized)

        case .pointer(let pointer):
            guard pointer.phase == .down else {
                return LunaFrameInvalidationSet(.input)
            }
            pointerAccentIsActive.toggle()
            moveCaret(to: pointer.location, extendingSelection: pointer.modifiers.shift)
            return LunaFrameInvalidationSet(.input)

        case .keyboard(let keyboard):
            keyboardEventCount &+= 1
            handleKeyboard(keyboard)
            return LunaFrameInvalidationSet(.input)

        case .textInput(let textInput):
            guard !textInput.text.isEmpty else { return LunaFrameInvalidationSet() }
            _ = MothEditorTransactions.insert(textInput.text, in: buffer, view: &primaryView)
            synchronizeViewsAfterSharedEdit()
            return LunaFrameInvalidationSet(.textInput)
        }
    }

    public mutating func render(into framebuffer: inout LunaFramebuffer) {
        let width = framebuffer.width
        let height = framebuffer.height

        let background = LunaRGBA8(r: 7, g: 7, b: 9)
        let chrome = LunaRGBA8(r: 19, g: 20, b: 22)
        let raised = LunaRGBA8(r: 36, g: 36, b: 38)
        let editor = LunaRGBA8(r: 15, g: 16, b: 19)
        let separator = LunaRGBA8(r: 56, g: 58, b: 64)
        let text = LunaRGBA8(r: 206, g: 209, b: 218)
        let mutedText = LunaRGBA8(r: 112, g: 116, b: 128)
        let accent = pointerAccentIsActive
            ? LunaRGBA8(r: 0, g: 122, b: 255)
            : LunaRGBA8(r: 112, g: 90, b: 255)

        framebuffer.clear(background)

        let statusHeight = 24
        let sidebarWidth = min(260, max(150, width / 4))
        let minimapWidth = min(110, max(60, width / 10))
        let contentTop = 68
        let contentHeight = max(1, height - contentTop - statusHeight)
        let editorBounds = LunaRectI(
            x: sidebarWidth + 1,
            y: contentTop,
            w: max(1, width - sidebarWidth - minimapWidth - 2),
            h: contentHeight
        )

        framebuffer.fillRect(LunaRectI(x: 0, y: 0, w: width, h: 30), color: chrome)
        framebuffer.fillRect(LunaRectI(x: 0, y: 30, w: width, h: 38), color: raised)
        framebuffer.fillRect(LunaRectI(x: 0, y: contentTop, w: sidebarWidth, h: contentHeight), color: chrome)
        framebuffer.fillRect(editorBounds, color: editor)
        framebuffer.fillRect(
            LunaRectI(x: max(sidebarWidth + 1, width - minimapWidth), y: contentTop, w: minimapWidth, h: contentHeight),
            color: LunaRGBA8(r: 12, g: 13, b: 16)
        )
        framebuffer.fillRect(
            LunaRectI(x: 0, y: max(0, height - statusHeight), w: width, h: statusHeight),
            color: raised
        )
        framebuffer.fillRect(LunaRectI(x: sidebarWidth, y: contentTop, w: 1, h: contentHeight), color: separator)
        framebuffer.fillRect(LunaRectI(x: 0, y: contentTop - 1, w: width, h: 1), color: separator)
        framebuffer.fillRect(LunaRectI(x: 10, y: 63, w: min(180, max(40, width / 5)), h: 3), color: accent)

        drawChromeText(
            framebuffer: &framebuffer,
            textColor: text,
            mutedText: mutedText,
            accent: accent,
            statusHeight: statusHeight
        )
        drawSidebar(framebuffer: &framebuffer, sidebarWidth: sidebarWidth, accent: accent, text: text, muted: mutedText)
        drawEditor(
            framebuffer: &framebuffer,
            bounds: editorBounds,
            textColor: text,
            mutedText: mutedText,
            accent: accent
        )
        drawMinimap(
            framebuffer: &framebuffer,
            left: max(sidebarWidth + 1, width - minimapWidth),
            top: contentTop,
            width: minimapWidth,
            height: contentHeight,
            accent: accent
        )
    }

    private mutating func handleKeyboard(_ event: LunaKeyboardEvent) {
        let snapshot = buffer.snapshot()

        switch event.key {
        case .backspace:
            _ = MothEditorTransactions.deleteBackward(in: buffer, view: &primaryView)
            synchronizeViewsAfterSharedEdit()

        case .delete:
            _ = MothEditorTransactions.deleteForward(in: buffer, view: &primaryView)
            synchronizeViewsAfterSharedEdit()

        case .enter:
            _ = MothEditorTransactions.insert("\n", in: buffer, view: &primaryView)
            synchronizeViewsAfterSharedEdit()

        case .arrowLeft:
            let next = MothTextOffset(rawValue: max(0, primaryView.caret.rawValue - 1))
            primaryView.setCaret(next, extendingSelection: event.modifiers.shift)
            _ = primaryView.synchronize(with: snapshot)

        case .arrowRight:
            let next = MothTextOffset(rawValue: min(snapshot.utf8Count, primaryView.caret.rawValue + 1))
            primaryView.setCaret(next, extendingSelection: event.modifiers.shift)
            _ = primaryView.synchronize(with: snapshot)

        case .home:
            let document = lunaSnapshot().staticDocument
            let location = document.location(forAbsoluteUTF8Offset: primaryView.caret.rawValue)
            let next = MothTextOffset(rawValue: document.absoluteUTF8Offset(for: LunaTextLocation(lineIndex: location.lineIndex, utf8Column: 0)))
            primaryView.setCaret(next, extendingSelection: event.modifiers.shift)

        case .end:
            let document = lunaSnapshot().staticDocument
            let location = document.location(forAbsoluteUTF8Offset: primaryView.caret.rawValue)
            let lineLength = document[line: location.lineIndex]?.utf8Length ?? 0
            let next = MothTextOffset(rawValue: document.absoluteUTF8Offset(for: LunaTextLocation(lineIndex: location.lineIndex, utf8Column: lineLength)))
            primaryView.setCaret(next, extendingSelection: event.modifiers.shift)

        case .arrowUp:
            moveCaretVertically(by: -1, extendingSelection: event.modifiers.shift)

        case .arrowDown:
            moveCaretVertically(by: 1, extendingSelection: event.modifiers.shift)

        case .pageUp:
            primaryView.viewport.firstVisibleLine = max(0, primaryView.viewport.firstVisibleLine - 12)

        case .pageDown:
            let lineCount = lunaSnapshot().staticDocument.lineCount
            primaryView.viewport.firstVisibleLine = min(max(0, lineCount - 1), primaryView.viewport.firstVisibleLine + 12)

        default:
            break
        }
    }

    private mutating func moveCaretVertically(by delta: Int, extendingSelection: Bool) {
        let document = lunaSnapshot().staticDocument
        let current = document.location(forAbsoluteUTF8Offset: primaryView.caret.rawValue)
        let preferred = primaryView.preferredUTF8Column ?? current.utf8Column
        let targetLine = min(max(0, current.lineIndex + delta), max(0, document.lineCount - 1))
        let targetColumn = min(preferred, document[line: targetLine]?.utf8Length ?? 0)
        let target = document.absoluteUTF8Offset(for: LunaTextLocation(lineIndex: targetLine, utf8Column: targetColumn))
        primaryView.setCaret(MothTextOffset(rawValue: target), extendingSelection: extendingSelection)
        primaryView.preferredUTF8Column = preferred

        let visibleRows = max(1, (framebufferSize.height - 68 - 24 - 20) / 18)
        if targetLine < primaryView.viewport.firstVisibleLine {
            primaryView.viewport.firstVisibleLine = targetLine
        } else if targetLine >= primaryView.viewport.firstVisibleLine + visibleRows {
            primaryView.viewport.firstVisibleLine = max(0, targetLine - visibleRows + 1)
        }
    }

    private mutating func moveCaret(to point: LunaPointI, extendingSelection: Bool) {
        let width = framebufferSize.width
        let height = framebufferSize.height
        let sidebarWidth = min(260, max(150, width / 4))
        let minimapWidth = min(110, max(60, width / 10))
        let contentTop = 68
        let statusHeight = 24
        let editorBounds = LunaRectI(
            x: sidebarWidth + 1,
            y: contentTop,
            w: max(1, width - sidebarWidth - minimapWidth - 2),
            h: max(1, height - contentTop - statusHeight)
        )
        guard editorBounds.contains(x: point.x, y: point.y) else { return }

        let document = lunaSnapshot().staticDocument
        let rowHeight = 18
        let gutterWidth = 48
        let line = primaryView.viewport.firstVisibleLine + max(0, (point.y - editorBounds.y - 10) / rowHeight)
        let clampedLine = min(max(0, line), max(0, document.lineCount - 1))
        let column = max(0, (point.x - editorBounds.x - gutterWidth - 10) / LunaDebugBitmapTextRenderer.advance)
        let clampedColumn = min(column, document[line: clampedLine]?.utf8Length ?? 0)
        let offset = document.absoluteUTF8Offset(for: LunaTextLocation(lineIndex: clampedLine, utf8Column: clampedColumn))
        primaryView.setCaret(MothTextOffset(rawValue: offset), extendingSelection: extendingSelection)
        primaryView.preferredUTF8Column = clampedColumn
    }

    private mutating func synchronizeViewsAfterSharedEdit() {
        let snapshot = buffer.snapshot()
        _ = primaryView.synchronize(with: snapshot)
        _ = secondaryView.synchronize(with: snapshot)
    }

    private func lunaSnapshot() -> LunaTextStorageSnapshot {
        MothLunaTextStorageAdapter(buffer: buffer).textSnapshot()
    }

    private func drawChromeText(
        framebuffer: inout LunaFramebuffer,
        textColor: LunaRGBA8,
        mutedText: LunaRGBA8,
        accent: LunaRGBA8,
        statusHeight: Int
    ) {
        LunaDebugBitmapTextRenderer.draw("MOTH TEXT", atX: 12, y: 10, color: textColor, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("File  Edit  Selection  Find  View  Goto  Tools", atX: 105, y: 10, color: mutedText, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("moth_phase_m1.txt", atX: 18, y: 45, color: textColor, into: &framebuffer)

        let snapshot = buffer.snapshot()
        let dirty = snapshot.isDirty ? "MODIFIED" : "SAVED"
        let status = "UTF-8   REV \(snapshot.revision.rawValue)   \(dirty)   2 VIEWS / 1 BUFFER"
        LunaDebugBitmapTextRenderer.draw(
            status,
            atX: 12,
            y: max(0, framebuffer.height - statusHeight + 8),
            color: snapshot.isDirty ? accent : mutedText,
            maximumWidth: max(0, framebuffer.width - 24),
            into: &framebuffer
        )
    }

    private func drawSidebar(
        framebuffer: inout LunaFramebuffer,
        sidebarWidth: Int,
        accent: LunaRGBA8,
        text: LunaRGBA8,
        muted: LunaRGBA8
    ) {
        LunaDebugBitmapTextRenderer.draw("OPEN FILES", atX: 16, y: 86, color: muted, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("moth_phase_m1.txt", atX: 28, y: 108, color: accent, maximumWidth: sidebarWidth - 38, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("PROJECT", atX: 16, y: 142, color: muted, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("Sources", atX: 28, y: 164, color: text, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("MothTextCore", atX: 40, y: 184, color: muted, maximumWidth: sidebarWidth - 50, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("MothEditor", atX: 40, y: 204, color: muted, maximumWidth: sidebarWidth - 50, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("MothApplication", atX: 40, y: 224, color: muted, maximumWidth: sidebarWidth - 50, into: &framebuffer)
    }

    private func drawEditor(
        framebuffer: inout LunaFramebuffer,
        bounds: LunaRectI,
        textColor: LunaRGBA8,
        mutedText: LunaRGBA8,
        accent: LunaRGBA8
    ) {
        let snapshot = lunaSnapshot()
        let document = snapshot.staticDocument
        let rowHeight = 18
        let gutterWidth = 48
        let firstLine = min(primaryView.viewport.firstVisibleLine, max(0, document.lineCount - 1))
        let maxRows = max(0, (bounds.h - 20) / rowHeight)
        let textX = bounds.x + gutterWidth + 10
        let maximumTextWidth = max(0, bounds.w - gutterWidth - 20)

        if let selection = primaryView.selection, !selection.isCollapsed {
            let range = selection.normalizedRange
            let start = document.location(forAbsoluteUTF8Offset: range.start.rawValue)
            let end = document.location(forAbsoluteUTF8Offset: range.end.rawValue)
            for lineIndex in start.lineIndex...end.lineIndex {
                guard lineIndex >= firstLine, lineIndex < firstLine + maxRows else { continue }
                let line = document[line: lineIndex]
                let startColumn = lineIndex == start.lineIndex ? start.utf8Column : 0
                let endColumn = lineIndex == end.lineIndex ? end.utf8Column : (line?.utf8Length ?? 0)
                guard endColumn > startColumn else { continue }
                let y = bounds.y + 10 + (lineIndex - firstLine) * rowHeight
                framebuffer.fillRect(
                    LunaRectI(
                        x: textX + startColumn * LunaDebugBitmapTextRenderer.advance,
                        y: y - 3,
                        w: max(1, (endColumn - startColumn) * LunaDebugBitmapTextRenderer.advance),
                        h: 12
                    ),
                    color: LunaRGBA8(r: 48, g: 58, b: 92)
                )
            }
        }

        for row in 0..<maxRows {
            let lineIndex = firstLine + row
            guard let line = document[line: lineIndex] else { break }
            let y = bounds.y + 10 + row * rowHeight
            LunaDebugBitmapTextRenderer.draw(
                String(line.lineNumber),
                atX: bounds.x + 10,
                y: y,
                color: mutedText,
                maximumWidth: gutterWidth - 14,
                into: &framebuffer
            )
            LunaDebugBitmapTextRenderer.draw(
                line.text.replacingOccurrences(of: "\t", with: "    "),
                atX: textX,
                y: y,
                color: textColor,
                maximumWidth: maximumTextWidth,
                into: &framebuffer
            )
        }

        let caretLocation = document.location(forAbsoluteUTF8Offset: primaryView.caret.rawValue)
        if caretLocation.lineIndex >= firstLine, caretLocation.lineIndex < firstLine + maxRows {
            let row = caretLocation.lineIndex - firstLine
            let caretX = textX + caretLocation.utf8Column * LunaDebugBitmapTextRenderer.advance
            let caretY = bounds.y + 7 + row * rowHeight
            framebuffer.fillRect(LunaRectI(x: caretX, y: caretY, w: 2, h: 12), color: accent)
        }
    }

    private func drawMinimap(
        framebuffer: inout LunaFramebuffer,
        left: Int,
        top: Int,
        width: Int,
        height: Int,
        accent: LunaRGBA8
    ) {
        let document = lunaSnapshot().staticDocument
        let usableWidth = max(8, width - 20)
        let rows = min(document.lineCount, max(0, (height - 20) / 6))
        for index in 0..<rows {
            guard let line = document[line: index] else { continue }
            let y = top + 10 + index * 6
            let length = min(usableWidth, max(2, line.utf8Length * 2))
            framebuffer.fillRect(
                LunaRectI(x: left + 10, y: y, w: length, h: 2),
                color: index == primaryView.viewport.firstVisibleLine
                    ? accent
                    : LunaRGBA8(r: 55, g: 58, b: 68)
            )
        }
    }

    public static let demoText = """
    // Moth Text M1.1
    // One authoritative source buffer; two independent editor views.

    import MothTextCore
    import MothEditor

    let buffer = MothInMemorySourceBuffer(text: "hello, Luna")
    var primary = MothEditorViewState(bufferID: buffer.id)
    var secondary = MothEditorViewState(
        bufferID: buffer.id,
        firstVisibleLine: 24
    )

    MothEditorTransactions.insert("!", in: buffer, view: &primary)
    // secondary observes the same revision without inheriting primary's caret.
    """
}
