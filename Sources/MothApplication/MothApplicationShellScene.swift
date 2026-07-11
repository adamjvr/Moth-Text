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
import Foundation
import LunaRender
import LunaUI
import MothEditor
import MothTextCore
import MothWorkspace

public struct MothApplicationShellScene {
    public private(set) var framebufferSize: LunaSizeI
    public private(set) var pointerAccentIsActive: Bool
    public private(set) var keyboardEventCount: UInt64
    public private(set) var document: MothFileDocument
    public private(set) var primaryView: MothEditorViewState
    public private(set) var secondaryView: MothEditorViewState
    public private(set) var statusMessage: String

    private var documentController: MothDocumentController<MothLocalDocumentFileAccess>
    private var dialogService: any LunaDialogService
    private var suppressedTextInput: String?

    public init(
        initialSize: LunaSizeI = LunaSizeI(width: 1100, height: 720),
        initialText: String = Self.demoText,
        dialogService: any LunaDialogService = LunaNoOpDialogService()
    ) {
        self.init(
            initialSize: initialSize,
            document: MothFileDocument(
                untitledText: initialText,
                displayName: "untitled.txt"
            ),
            dialogService: dialogService
        )
    }

    public init(
        initialSize: LunaSizeI = LunaSizeI(width: 1100, height: 720),
        document: MothFileDocument,
        dialogService: any LunaDialogService = LunaNoOpDialogService()
    ) {
        self.framebufferSize = initialSize
        self.pointerAccentIsActive = false
        self.keyboardEventCount = 0
        self.document = document
        self.documentController = MothDocumentController(fileAccess: MothLocalDocumentFileAccess())
        self.dialogService = dialogService
        self.suppressedTextInput = nil
        self.statusMessage = document.snapshot().isUntitled
            ? "Untitled document — Ctrl+Shift+S to Save As"
            : "Opened \(document.snapshot().displayPath)"

        let buffer = document.buffer
        self.primaryView = MothEditorViewState(
            bufferID: buffer.id,
            caret: .zero,
            viewport: MothEditorViewportState(firstVisibleLine: 0)
        )
        self.secondaryView = MothEditorViewState(
            bufferID: buffer.id,
            caret: MothTextOffset(rawValue: buffer.snapshot().utf8Count),
            preferredUTF8Column: 12,
            viewport: MothEditorViewportState(firstVisibleLine: 2)
        )
        synchronizeViewsAfterDocumentInstall()
    }

    public var buffer: MothInMemorySourceBuffer { document.buffer }
    public var documentSnapshot: MothDocumentSnapshot { document.snapshot() }
    public var wantsContinuousRendering: Bool { false }
    public var bufferSnapshot: MothSourceBufferSnapshot { buffer.snapshot() }

    public mutating func openDocument(at url: URL) throws {
        install(document: try documentController.open(url: url))
        statusMessage = "Opened \(document.snapshot().displayPath)"
    }

    @discardableResult
    public mutating func saveDocument() throws -> MothDocumentSnapshot {
        let saved = try documentController.save(document)
        statusMessage = "Saved \(saved.displayPath)"
        return saved
    }

    @discardableResult
    public mutating func saveDocumentAs(
        to url: URL,
        allowsOverwrite: Bool = false
    ) throws -> MothDocumentSnapshot {
        let saved = try documentController.saveAs(
            document,
            to: url,
            allowsOverwrite: allowsOverwrite
        )
        statusMessage = "Saved \(saved.displayPath)"
        return saved
    }

    public mutating func hasExternalFileChange() throws -> Bool {
        try documentController.hasExternalChange(document)
    }

    /// Resolve dirty-document policy before the native host terminates.
    /// Returning false leaves the application running.
    public mutating func requestApplicationTermination() -> Bool {
        prepareToReplaceOrCloseCurrentDocument(source: "window.close")
    }

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
            if let suppressedTextInput, textInput.text.lowercased() == suppressedTextInput {
                self.suppressedTextInput = nil
                return LunaFrameInvalidationSet(.input)
            }
            suppressedTextInput = nil
            _ = MothEditorTransactions.insert(textInput.text, in: buffer, view: &primaryView)
            synchronizeViewsAfterSharedEdit()
            return LunaFrameInvalidationSet(.textInput)
        }
    }

    public mutating func render(into framebuffer: inout LunaFramebuffer) {
        let width = framebuffer.width
        let height = framebuffer.height

        let palette = MothApplicationTheme.renderPalette
        let background = palette.windowBackground
        let chrome = palette.chromeBackground
        let raised = palette.raisedBackground
        let editor = palette.editorBackground
        let separator = palette.separator
        let text = palette.text
        let mutedText = palette.mutedText
        let accent = pointerAccentIsActive ? palette.accentStrong : palette.accent
        let minimapBackground = palette.minimapBackground

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
            color: minimapBackground
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
        if handleApplicationShortcut(event) { return }
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

    private mutating func handleApplicationShortcut(_ event: LunaKeyboardEvent) -> Bool {
        guard event.modifiers.control || event.modifiers.command else { return false }
        guard case .other(let rawKey) = event.key else { return false }
        let key = rawKey.lowercased()

        switch key {
        case "o":
            suppressedTextInput = key
            requestOpenDocument()
            return true
        case "s":
            suppressedTextInput = key
            if event.modifiers.shift {
                _ = requestSaveDocumentAs()
            } else if document.snapshot().isUntitled {
                _ = requestSaveDocumentAs()
            } else {
                do {
                    _ = try saveDocument()
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
            return true
        default:
            return false
        }
    }

    private mutating func requestOpenDocument() {
        let current = document.snapshot()
        let result = dialogService.chooseFileToOpen(
            LunaFileDialogRequest(
                purpose: .open,
                title: "Open File",
                defaultDirectory: current.fileURL?.deletingLastPathComponent().path,
                allowedExtensions: [],
                allowsMultipleSelection: false,
                source: "moth.command.open"
            )
        )
        guard result.didSelect, let path = result.firstSelectedPath else {
            statusMessage = result.statusMessage ?? "Open cancelled"
            return
        }
        guard prepareToReplaceOrCloseCurrentDocument(source: "command.open") else { return }
        do {
            try openDocument(at: URL(fileURLWithPath: path))
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    private mutating func requestSaveDocumentAs() -> Bool {
        let current = document.snapshot()
        let result = dialogService.chooseFileToSave(
            LunaFileDialogRequest(
                purpose: .save,
                title: "Save File As",
                defaultDirectory: current.fileURL?.deletingLastPathComponent().path,
                defaultFileName: current.displayName,
                allowedExtensions: [],
                allowsMultipleSelection: false,
                source: "moth.command.saveAs"
            )
        )
        guard result.didSelect, let path = result.firstSelectedPath else {
            statusMessage = result.statusMessage ?? "Save As cancelled"
            return false
        }
        do {
            _ = try saveDocumentAs(
                to: URL(fileURLWithPath: path),
                allowsOverwrite: result.allowsOverwrite
            )
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private mutating func prepareToReplaceOrCloseCurrentDocument(source: String) -> Bool {
        let snapshot = document.snapshot()
        guard snapshot.isDirty else { return true }

        let result = dialogService.confirmUnsavedChanges(
            LunaUnsavedChangesDialogRequest(
                documentID: snapshot.id.description,
                title: snapshot.displayName,
                displayPath: snapshot.fileURL?.path,
                isUntitled: snapshot.isUntitled,
                source: source
            )
        )

        switch result.decision {
        case .discard:
            statusMessage = result.statusMessage ?? "Discarding unsaved changes"
            return true

        case .cancel:
            statusMessage = result.statusMessage ?? "Close cancelled"
            return false

        case .save:
            if snapshot.isUntitled {
                return requestSaveDocumentAs()
            }
            do {
                _ = try saveDocument()
                return true
            } catch {
                statusMessage = error.localizedDescription
                return false
            }
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

    private mutating func install(document: MothFileDocument) {
        self.document = document
        let snapshot = document.buffer.snapshot()
        primaryView = MothEditorViewState(
            bufferID: document.buffer.id,
            caret: .zero,
            viewport: MothEditorViewportState(firstVisibleLine: 0)
        )
        secondaryView = MothEditorViewState(
            bufferID: document.buffer.id,
            caret: MothTextOffset(rawValue: snapshot.utf8Count),
            preferredUTF8Column: 12,
            viewport: MothEditorViewportState(firstVisibleLine: min(2, max(0, snapshot.text.split(separator: "\n", omittingEmptySubsequences: false).count - 1)))
        )
        synchronizeViewsAfterDocumentInstall()
    }

    private mutating func synchronizeViewsAfterDocumentInstall() {
        let snapshot = buffer.snapshot()
        _ = primaryView.synchronize(with: snapshot)
        _ = secondaryView.synchronize(with: snapshot)
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
        textColor: LunaRender.LunaRGBA8,
        mutedText: LunaRender.LunaRGBA8,
        accent: LunaRender.LunaRGBA8,
        statusHeight: Int
    ) {
        LunaDebugBitmapTextRenderer.draw("MOTH TEXT", atX: 12, y: 10, color: textColor, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("File  Edit  Selection  Find  View  Goto  Tools", atX: 105, y: 10, color: mutedText, into: &framebuffer)
        let documentSnapshot = document.snapshot()
        let tabTitle = documentSnapshot.isDirty ? "• \(documentSnapshot.displayName)" : documentSnapshot.displayName
        LunaDebugBitmapTextRenderer.draw(tabTitle, atX: 18, y: 45, color: textColor, into: &framebuffer)

        let snapshot = documentSnapshot.buffer
        let dirty = snapshot.isDirty ? "MODIFIED" : "SAVED"
        let status = "\(documentSnapshot.encoding.displayName)   REV \(snapshot.revision.rawValue)   \(dirty)   \(statusMessage)"
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
        accent: LunaRender.LunaRGBA8,
        text: LunaRender.LunaRGBA8,
        muted: LunaRender.LunaRGBA8
    ) {
        LunaDebugBitmapTextRenderer.draw("OPEN FILES", atX: 16, y: 86, color: muted, into: &framebuffer)
        let snapshot = document.snapshot()
        LunaDebugBitmapTextRenderer.draw(snapshot.displayName, atX: 28, y: 108, color: accent, maximumWidth: sidebarWidth - 38, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("DOCUMENT", atX: 16, y: 142, color: muted, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw(snapshot.isUntitled ? "UNTITLED" : "FILE-BACKED", atX: 28, y: 164, color: text, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw(snapshot.encoding.displayName, atX: 40, y: 184, color: muted, maximumWidth: sidebarWidth - 50, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw(snapshot.displayPath, atX: 40, y: 204, color: muted, maximumWidth: sidebarWidth - 50, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("Ctrl+O Open   Ctrl+S Save", atX: 28, y: 236, color: muted, maximumWidth: sidebarWidth - 38, into: &framebuffer)
    }

    private func drawEditor(
        framebuffer: inout LunaFramebuffer,
        bounds: LunaRectI,
        textColor: LunaRender.LunaRGBA8,
        mutedText: LunaRender.LunaRGBA8,
        accent: LunaRender.LunaRGBA8
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
                    color: MothApplicationTheme.renderPalette.selection
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
        accent: LunaRender.LunaRGBA8
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
                    : LunaRender.LunaRGBA8(r: 55, g: 58, b: 68)
            )
        }
    }

    public static let demoText = """
    // Moth Text M2.1
    // File-backed documents now own URL, encoding, save state, and one shared buffer.

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
