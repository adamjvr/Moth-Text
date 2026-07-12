// SPDX-License-Identifier: MPL-2.0
//
// MothApplicationShellScene.swift
//
// Luna-rendered Moth editor slice backed by one real Moth-owned file document.
// Luna owns pane geometry, wrapping, clipping, hit testing, and platform input.
// Moth owns the document, transactions, dirty state, and independent view state.

import Foundation
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaUI
import MothEditor
import MothTextCore
import MothWorkspace

public struct MothApplicationShellScene {
    static let primaryPaneID = LunaPaneID(rawValue: "moth.primary")
    static let secondaryPaneID = LunaPaneID(rawValue: "moth.secondary")
    static let mainSplitID = LunaSplitID(rawValue: "moth.main-split")

    public private(set) var framebufferSize: LunaSizeI
    public private(set) var pointerAccentIsActive: Bool
    public private(set) var keyboardEventCount: UInt64
    public private(set) var document: MothFileDocument
    public private(set) var primaryView: MothEditorViewState
    public private(set) var secondaryView: MothEditorViewState
    public private(set) var paneWorkspace: LunaPaneWorkspaceState
    public private(set) var statusMessage: String

    private var documentController: MothDocumentController<MothLocalDocumentFileAccess>
    private var dialogService: any LunaDialogService
    private var suppressedTextInput: String?
    private var paneInteractionState: LunaPaneContainerInteractionState
    private var textSelectionInteractionState: LunaTextSelectionInteractionState
    private var currentCursorIntent: LunaCursorIntent

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
        self.paneInteractionState = LunaPaneContainerInteractionState()
        self.textSelectionInteractionState = LunaTextSelectionInteractionState()
        self.currentCursorIntent = .arrow
        self.statusMessage = document.snapshot().isUntitled
            ? "Untitled document — Ctrl+Shift+S to Save As"
            : "Opened \(document.snapshot().displayPath)"

        self.paneWorkspace = LunaPaneWorkspaceState(
            root: .split(
                id: Self.mainSplitID,
                axis: .horizontal,
                fraction: 0.58,
                first: .pane(Self.primaryPaneID),
                second: .pane(Self.secondaryPaneID)
            ),
            activePaneID: Self.primaryPaneID,
            minimumSplitFraction: 0.2,
            maximumSplitFraction: 0.8
        )

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
    public var wantsContinuousRendering: Bool { textSelectionInteractionState.wantsContinuousUpdates }
    public var cursorIntent: LunaCursorIntent { currentCursorIntent }
    public var wantsPointerCapture: Bool {
        paneInteractionState.wantsPointerCapture || textSelectionInteractionState.wantsPointerCapture
    }
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
            resetWrappedScrollAnchors()
            return LunaFrameInvalidationSet(.windowResized)

        case .pointerCaptureLost:
            paneInteractionState.cancelDrag()
            paneInteractionState.hoveredSplitID = nil
            textSelectionInteractionState.cancel()
            currentCursorIntent = .arrow
            statusMessage = "Pointer selection/resize cancelled after capture loss"
            return LunaFrameInvalidationSet(.input)

        case .pointer(let pointer):
            handlePointer(pointer)
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
            let sourceBuffer = buffer
            mutateActiveView { view in
                _ = MothEditorTransactions.insert(textInput.text, in: sourceBuffer, view: &view)
            }
            synchronizeViewsAfterSharedEdit()
            ensureActiveCaretVisible()
            return LunaFrameInvalidationSet(.textInput)
        }
    }

    public mutating func render(into framebuffer: inout LunaFramebuffer) {
        advanceTextSelectionAutoscroll()
        let width = framebuffer.width
        let height = framebuffer.height
        let palette = MothApplicationTheme.renderPalette

        framebuffer.clear(palette.windowBackground)

        let statusHeight = 24
        let sidebarWidth = min(260, max(150, width / 4))
        let minimapWidth = min(110, max(60, width / 10))
        let contentTop = 68
        let contentHeight = max(1, height - contentTop - statusHeight)
        let paneBounds = LunaRectI(
            x: sidebarWidth + 1,
            y: contentTop,
            w: max(1, width - sidebarWidth - minimapWidth - 2),
            h: contentHeight
        )

        framebuffer.fillRect(LunaRectI(x: 0, y: 0, w: width, h: 30), color: palette.chromeBackground)
        framebuffer.fillRect(LunaRectI(x: 0, y: 30, w: width, h: 38), color: palette.raisedBackground)
        framebuffer.fillRect(LunaRectI(x: 0, y: contentTop, w: sidebarWidth, h: contentHeight), color: palette.chromeBackground)
        framebuffer.fillRect(
            LunaRectI(x: max(sidebarWidth + 1, width - minimapWidth), y: contentTop, w: minimapWidth, h: contentHeight),
            color: palette.minimapBackground
        )
        framebuffer.fillRect(
            LunaRectI(x: 0, y: max(0, height - statusHeight), w: width, h: statusHeight),
            color: palette.raisedBackground
        )
        framebuffer.fillRect(LunaRectI(x: sidebarWidth, y: contentTop, w: 1, h: contentHeight), color: palette.separator)
        framebuffer.fillRect(LunaRectI(x: 0, y: contentTop - 1, w: width, h: 1), color: palette.separator)
        framebuffer.fillRect(LunaRectI(x: 10, y: 63, w: min(180, max(40, width / 5)), h: 3), color: activeAccent)

        drawChromeText(framebuffer: &framebuffer, statusHeight: statusHeight)
        drawSidebar(framebuffer: &framebuffer, sidebarWidth: sidebarWidth)
        drawPaneEditors(framebuffer: &framebuffer, bounds: paneBounds)
        drawMinimap(
            framebuffer: &framebuffer,
            left: max(sidebarWidth + 1, width - minimapWidth),
            top: contentTop,
            width: minimapWidth,
            height: contentHeight,
            accent: activeAccent
        )
    }

    // MARK: - Pane integration

    var activePaneID: LunaPaneID { paneWorkspace.activePaneID }

    func paneContainer(bounds: LunaRectI? = nil) -> LunaPaneContainer {
        LunaPaneContainer(
            id: LunaNodeID(rawValue: "moth.editor.panes"),
            bounds: bounds ?? paneEditorBounds(),
            state: paneWorkspace,
            interactionState: paneInteractionState,
            theme: MothApplicationTheme.theme,
            metrics: LunaPaneContainerMetrics(
                dividerThickness: 11,
                dividerRuleThickness: 1,
                minimumPaneExtent: 120,
                activePaneBorderThickness: 2
            )
        )
    }

    func paneLayout(bounds: LunaRectI? = nil) -> LunaPaneContainerLayout {
        paneContainer(bounds: bounds).layout()
    }

    func paneContentFrame(for paneID: LunaPaneID) -> LunaPaneContentFrame? {
        paneLayout().contentFrame(for: paneID, metrics: .editor)
    }

    func paneTextView(for paneID: LunaPaneID) -> LunaStaticTextView? {
        guard let frame = paneContentFrame(for: paneID) else { return nil }
        return makePaneSurface(paneID: paneID, contentFrame: frame).textView
    }

    private func paneEditorBounds() -> LunaRectI {
        let width = framebufferSize.width
        let height = framebufferSize.height
        let sidebarWidth = min(260, max(150, width / 4))
        let minimapWidth = min(110, max(60, width / 10))
        let contentTop = 68
        let statusHeight = 24
        return LunaRectI(
            x: sidebarWidth + 1,
            y: contentTop,
            w: max(1, width - sidebarWidth - minimapWidth - 2),
            h: max(1, height - contentTop - statusHeight)
        )
    }

    private func makePaneSurface(
        paneID: LunaPaneID,
        contentFrame: LunaPaneContentFrame
    ) -> MothPaneEditorSurface {
        MothPaneEditorSurface(
            paneID: paneID,
            contentFrame: contentFrame,
            viewState: viewState(for: paneID),
            snapshot: lunaSnapshot(),
            isActive: paneID == paneWorkspace.activePaneID
        )
    }

    private func resolvedCursorIntent(at point: LunaPointI) -> LunaCursorIntent {
        if textSelectionInteractionState.isSelecting { return .text }
        let container = paneContainer()
        if let dividerIntent = container.cursorIntent(at: point) {
            return dividerIntent
        }
        if let pane = paneLayout().paneFrames.first(where: { $0.bounds.contains(x: point.x, y: point.y) }),
           let content = paneContentFrame(for: pane.paneID),
           content.contentBounds.contains(x: point.x, y: point.y) {
            return .text
        }
        return .arrow
    }

    private mutating func handlePointer(_ event: LunaPointerEvent) {
        if event.phase == .down { pointerAccentIsActive.toggle() }

        let wasDraggingDivider = paneInteractionState.isDraggingDivider
        let container = paneContainer()
        var workspace = paneWorkspace
        var paneInteraction = paneInteractionState
        let paneResult = container.handlePointerEvent(
            event,
            state: &workspace,
            interactionState: &paneInteraction
        )
        paneWorkspace = workspace
        paneInteractionState = paneInteraction
        currentCursorIntent = resolvedCursorIntent(at: event.location)

        let ownsDividerGesture = wasDraggingDivider || paneInteraction.isDraggingDivider || paneResult.resizedSplitID != nil
        if ownsDividerGesture {
            textSelectionInteractionState.cancel()
            resetWrappedScrollAnchors()
            statusMessage = paneInteraction.isDraggingDivider
                ? "Resizing editor panes"
                : "Editor pane resize complete"
            return
        }

        let target: (paneID: LunaPaneID, surface: MothPaneEditorSurface)?
        if event.phase == .down {
            target = paneSurface(at: event.location)
        } else {
            target = paneSurface(forTextSurfaceID: textSelectionInteractionState.activeSurfaceID)
        }

        guard let target else {
            if event.phase == .down { textSelectionInteractionState.cancel() }
            currentCursorIntent = resolvedCursorIntent(at: event.location)
            return
        }

        let textView = target.surface.textView
        let presentation = viewState(for: target.paneID)
        let currentCaret = textView.document.location(
            forAbsoluteUTF8Offset: presentation.caret.rawValue
        )
        let currentSelection = presentation.selection.map {
            LunaTextRange(
                anchor: textView.document.location(forAbsoluteUTF8Offset: $0.anchor.rawValue),
                focus: textView.document.location(forAbsoluteUTF8Offset: $0.focus.rawValue)
            )
        }

        var selectionInteraction = textSelectionInteractionState
        let selectionResult = LunaTextSelectionInteraction.handlePointerEvent(
            event,
            in: textView,
            currentCaret: currentCaret,
            currentSelection: currentSelection,
            state: &selectionInteraction
        )
        textSelectionInteractionState = selectionInteraction
        currentCursorIntent = resolvedCursorIntent(at: event.location)

        guard selectionResult.didConsumeEvent else { return }
        applyTextSelectionResult(selectionResult, paneID: target.paneID, textView: textView)
        let selectedBytes = viewState(for: target.paneID).selection?.normalizedRange.length ?? 0
        let gesture: String
        switch selectionResult.granularity ?? selectionInteraction.granularity {
        case .character: gesture = selectionResult.didEndGesture ? "selection complete" : "drag selection"
        case .word: gesture = "word selection"
        case .line: gesture = "line selection"
        }
        statusMessage = "C1B \(gesture) in \(target.paneID.rawValue): bytes=\(selectedBytes)"
    }

    private func paneSurface(at point: LunaPointI) -> (paneID: LunaPaneID, surface: MothPaneEditorSurface)? {
        let layout = paneLayout()
        guard let frame = layout.contentFrames(metrics: .editor).first(where: {
            $0.contentBounds.contains(x: point.x, y: point.y)
        }) else { return nil }
        return (frame.paneID, makePaneSurface(paneID: frame.paneID, contentFrame: frame))
    }

    private func paneSurface(
        forTextSurfaceID surfaceID: LunaNodeID?
    ) -> (paneID: LunaPaneID, surface: MothPaneEditorSurface)? {
        guard let surfaceID else { return nil }
        let layout = paneLayout()
        for frame in layout.contentFrames(metrics: .editor) {
            let surface = makePaneSurface(paneID: frame.paneID, contentFrame: frame)
            if surface.textView.id == surfaceID { return (frame.paneID, surface) }
        }
        return nil
    }

    private mutating func applyTextSelectionResult(
        _ result: LunaTextSelectionInteractionResult,
        paneID: LunaPaneID,
        textView: LunaStaticTextView
    ) {
        if result.requestedVisualRowDelta != 0 {
            let scrolled = textView.scrolled(byLineDelta: result.requestedVisualRowDelta)
            mutateView(for: paneID) { view in
                view.viewport.firstVisibleLine = scrolled.scrollTopLine
                view.viewport.firstVisibleVisualRow = scrolled.scrollTopVisualRow
            }
        }
        guard result.didChangeSelection, let selection = result.selection else { return }
        let anchor = MothTextOffset(
            rawValue: textView.document.absoluteUTF8Offset(for: selection.anchor)
        )
        let focus = MothTextOffset(
            rawValue: textView.document.absoluteUTF8Offset(for: selection.focus)
        )
        mutateView(for: paneID) { view in
            view.setSelection(anchor: anchor, focus: focus)
            view.preferredUTF8Column = selection.focus.utf8Column
        }
    }

    private mutating func advanceTextSelectionAutoscroll() {
        guard textSelectionInteractionState.wantsContinuousUpdates,
              let target = paneSurface(forTextSurfaceID: textSelectionInteractionState.activeSurfaceID)
        else { return }

        var interaction = textSelectionInteractionState
        let result = LunaTextSelectionInteraction.advanceAutoscroll(
            in: target.surface.textView,
            state: &interaction
        )
        textSelectionInteractionState = interaction
        guard result.requestedVisualRowDelta != 0 || result.didChangeSelection else { return }
        applyTextSelectionResult(result, paneID: target.paneID, textView: target.surface.textView)
        statusMessage = "C1B edge autoscroll in \(target.paneID.rawValue)"
    }

    private mutating func resetWrappedScrollAnchors() {
        primaryView.viewport.firstVisibleVisualRow = nil
        secondaryView.viewport.firstVisibleVisualRow = nil
    }

    // MARK: - Editing and commands

    private mutating func handleKeyboard(_ event: LunaKeyboardEvent) {
        if handleApplicationShortcut(event) { return }
        let snapshot = buffer.snapshot()

        switch event.key {
        case .backspace:
            let sourceBuffer = buffer
            mutateActiveView { view in
                _ = MothEditorTransactions.deleteBackward(in: sourceBuffer, view: &view)
            }
            synchronizeViewsAfterSharedEdit()
            ensureActiveCaretVisible()

        case .delete:
            let sourceBuffer = buffer
            mutateActiveView { view in
                _ = MothEditorTransactions.deleteForward(in: sourceBuffer, view: &view)
            }
            synchronizeViewsAfterSharedEdit()
            ensureActiveCaretVisible()

        case .enter:
            let sourceBuffer = buffer
            mutateActiveView { view in
                _ = MothEditorTransactions.insert("\n", in: sourceBuffer, view: &view)
            }
            synchronizeViewsAfterSharedEdit()
            ensureActiveCaretVisible()

        case .arrowLeft:
            mutateActiveView { view in
                let next = MothTextOffset(rawValue: max(0, view.caret.rawValue - 1))
                view.setCaret(next, extendingSelection: event.modifiers.shift)
                _ = view.synchronize(with: snapshot)
            }
            ensureActiveCaretVisible()

        case .arrowRight:
            mutateActiveView { view in
                let next = MothTextOffset(rawValue: min(snapshot.utf8Count, view.caret.rawValue + 1))
                view.setCaret(next, extendingSelection: event.modifiers.shift)
                _ = view.synchronize(with: snapshot)
            }
            ensureActiveCaretVisible()

        case .home:
            moveActiveCaretToLineBoundary(end: false, extendingSelection: event.modifiers.shift)

        case .end:
            moveActiveCaretToLineBoundary(end: true, extendingSelection: event.modifiers.shift)

        case .arrowUp:
            moveActiveCaretVertically(by: -1, extendingSelection: event.modifiers.shift)

        case .arrowDown:
            moveActiveCaretVertically(by: 1, extendingSelection: event.modifiers.shift)

        case .pageUp:
            scrollActivePane(byVisualRows: -12)

        case .pageDown:
            scrollActivePane(byVisualRows: 12)

        default:
            break
        }
    }

    private mutating func handleApplicationShortcut(_ event: LunaKeyboardEvent) -> Bool {
        guard event.modifiers.control || event.modifiers.command else { return false }

        if event.key == .tab {
            _ = paneWorkspace.traverse(event.modifiers.shift ? .previous : .next, layout: paneLayout())
            return true
        }

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

    private mutating func moveActiveCaretToLineBoundary(end: Bool, extendingSelection: Bool) {
        let document = lunaSnapshot().staticDocument
        let view = activeViewState
        let location = document.location(forAbsoluteUTF8Offset: view.caret.rawValue)
        let column = end ? (document[line: location.lineIndex]?.utf8Length ?? 0) : 0
        let offset = document.absoluteUTF8Offset(
            for: LunaTextLocation(lineIndex: location.lineIndex, utf8Column: column)
        )
        mutateActiveView { view in
            view.setCaret(MothTextOffset(rawValue: offset), extendingSelection: extendingSelection)
            view.preferredUTF8Column = column
        }
        ensureActiveCaretVisible()
    }

    private mutating func moveActiveCaretVertically(by delta: Int, extendingSelection: Bool) {
        let document = lunaSnapshot().staticDocument
        let view = activeViewState
        let current = document.location(forAbsoluteUTF8Offset: view.caret.rawValue)
        let preferred = view.preferredUTF8Column ?? current.utf8Column
        let targetLine = min(max(0, current.lineIndex + delta), max(0, document.lineCount - 1))
        let targetColumn = min(preferred, document[line: targetLine]?.utf8Length ?? 0)
        let target = document.absoluteUTF8Offset(
            for: LunaTextLocation(lineIndex: targetLine, utf8Column: targetColumn)
        )
        mutateActiveView { view in
            view.setCaret(MothTextOffset(rawValue: target), extendingSelection: extendingSelection)
            view.preferredUTF8Column = preferred
        }
        ensureActiveCaretVisible()
    }

    private mutating func scrollActivePane(byVisualRows delta: Int) {
        let paneID = paneWorkspace.activePaneID
        guard let textView = paneTextView(for: paneID) else { return }
        let scrolled = textView.scrolled(byLineDelta: delta)
        let layout = scrolled.layout()
        mutateView(for: paneID) { view in
            view.viewport.firstVisibleLine = layout.firstVisibleLineIndex
            view.viewport.firstVisibleVisualRow = layout.firstVisibleVisualRowIndex
        }
    }

    private mutating func ensureActiveCaretVisible() {
        let paneID = paneWorkspace.activePaneID
        guard let textView = paneTextView(for: paneID) else { return }
        let document = textView.document
        let location = document.location(forAbsoluteUTF8Offset: activeViewState.caret.rawValue)
        let ensured = textView.ensuringVisible(location)
        let layout = ensured.layout()
        mutateView(for: paneID) { view in
            view.viewport.firstVisibleLine = layout.firstVisibleLineIndex
            view.viewport.firstVisibleVisualRow = layout.firstVisibleVisualRowIndex
        }
    }

    private var activeViewState: MothEditorViewState {
        viewState(for: paneWorkspace.activePaneID)
    }

    private func viewState(for paneID: LunaPaneID) -> MothEditorViewState {
        paneID == Self.secondaryPaneID ? secondaryView : primaryView
    }

    private mutating func mutateActiveView(_ body: (inout MothEditorViewState) -> Void) {
        mutateView(for: paneWorkspace.activePaneID, body)
    }

    private mutating func mutateView(
        for paneID: LunaPaneID,
        _ body: (inout MothEditorViewState) -> Void
    ) {
        if paneID == Self.secondaryPaneID {
            body(&secondaryView)
        } else {
            body(&primaryView)
        }
    }

    // MARK: - File workflow

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
            if snapshot.isUntitled { return requestSaveDocumentAs() }
            do {
                _ = try saveDocument()
                return true
            } catch {
                statusMessage = error.localizedDescription
                return false
            }
        }
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
            viewport: MothEditorViewportState(
                firstVisibleLine: min(
                    2,
                    max(0, snapshot.text.split(separator: "\n", omittingEmptySubsequences: false).count - 1)
                )
            )
        )
        paneWorkspace.activePaneID = Self.primaryPaneID
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

    // MARK: - Drawing

    private var activeAccent: LunaRender.LunaRGBA8 {
        let palette = MothApplicationTheme.renderPalette
        return pointerAccentIsActive ? palette.accentStrong : palette.accent
    }

    private func drawChromeText(
        framebuffer: inout LunaFramebuffer,
        statusHeight: Int
    ) {
        let palette = MothApplicationTheme.renderPalette
        LunaDebugBitmapTextRenderer.draw("MOTH TEXT", atX: 12, y: 10, color: palette.text, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw(
            "File  Edit  Selection  Find  View  Goto  Tools",
            atX: 105,
            y: 10,
            color: palette.mutedText,
            into: &framebuffer
        )
        let documentSnapshot = document.snapshot()
        let tabTitle = documentSnapshot.isDirty ? "• \(documentSnapshot.displayName)" : documentSnapshot.displayName
        LunaDebugBitmapTextRenderer.draw(tabTitle, atX: 18, y: 45, color: palette.text, into: &framebuffer)

        let snapshot = documentSnapshot.buffer
        let dirty = snapshot.isDirty ? "MODIFIED" : "SAVED"
        let pane = paneWorkspace.activePaneID == Self.primaryPaneID ? "PRIMARY" : "SECONDARY"
        let status = "\(documentSnapshot.encoding.displayName)   REV \(snapshot.revision.rawValue)   \(dirty)   \(pane)   \(statusMessage)"
        LunaDebugBitmapTextRenderer.draw(
            status,
            atX: 12,
            y: max(0, framebuffer.height - statusHeight + 8),
            color: snapshot.isDirty ? activeAccent : palette.mutedText,
            maximumWidth: max(0, framebuffer.width - 24),
            into: &framebuffer
        )
    }

    private func drawSidebar(
        framebuffer: inout LunaFramebuffer,
        sidebarWidth: Int
    ) {
        let palette = MothApplicationTheme.renderPalette
        LunaDebugBitmapTextRenderer.draw("OPEN FILES", atX: 16, y: 86, color: palette.mutedText, into: &framebuffer)
        let snapshot = document.snapshot()
        LunaDebugBitmapTextRenderer.draw(snapshot.displayName, atX: 28, y: 108, color: activeAccent, maximumWidth: sidebarWidth - 38, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("DOCUMENT", atX: 16, y: 142, color: palette.mutedText, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw(snapshot.isUntitled ? "UNTITLED" : "FILE-BACKED", atX: 28, y: 164, color: palette.text, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw(snapshot.encoding.displayName, atX: 40, y: 184, color: palette.mutedText, maximumWidth: sidebarWidth - 50, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw(snapshot.displayPath, atX: 40, y: 204, color: palette.mutedText, maximumWidth: sidebarWidth - 50, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("Ctrl+O Open   Ctrl+S Save", atX: 28, y: 236, color: palette.mutedText, maximumWidth: sidebarWidth - 38, into: &framebuffer)
        LunaDebugBitmapTextRenderer.draw("Ctrl+Tab switches panes", atX: 28, y: 256, color: palette.mutedText, maximumWidth: sidebarWidth - 38, into: &framebuffer)
    }

    private func drawPaneEditors(
        framebuffer: inout LunaFramebuffer,
        bounds: LunaRectI
    ) {
        let palette = MothApplicationTheme.renderPalette
        let container = paneContainer(bounds: bounds)
        let layout = container.layout()
        let frames = layout.contentFrames(metrics: .editor)

        for frame in frames {
            framebuffer.fillRect(frame.headerBounds, color: palette.raisedBackground)
            let active = frame.paneID == paneWorkspace.activePaneID
            let title = frame.paneID == Self.primaryPaneID ? "PRIMARY VIEW" : "SECONDARY VIEW"
            let view = viewState(for: frame.paneID)
            let header = active ? "● \(title)" : "  \(title)"
            LunaDebugBitmapTextRenderer.draw(
                header,
                atX: frame.headerBounds.x + 8,
                y: frame.headerBounds.y + 7,
                color: active ? activeAccent : palette.mutedText,
                maximumWidth: max(0, frame.headerBounds.w - 16),
                into: &framebuffer
            )
            let scroll = view.viewport.firstVisibleVisualRow.map { "ROW \($0)" }
                ?? "LINE \(view.viewport.firstVisibleLine + 1)"
            LunaDebugBitmapTextRenderer.draw(
                scroll,
                atX: max(frame.headerBounds.x + 8, frame.headerBounds.x + frame.headerBounds.w - 72),
                y: frame.headerBounds.y + 7,
                color: palette.mutedText,
                maximumWidth: 64,
                into: &framebuffer
            )
            makePaneSurface(paneID: frame.paneID, contentFrame: frame).draw(into: &framebuffer)
        }

        for divider in layout.dividerFrames {
            framebuffer.fillRect(divider.bounds, color: palette.separator)
        }

        if let active = layout.paneFrame(for: paneWorkspace.activePaneID) {
            let b = active.bounds
            let c = activeAccent
            framebuffer.fillRect(LunaRectI(x: b.x, y: b.y, w: b.w, h: 2), color: c)
            framebuffer.fillRect(LunaRectI(x: b.x, y: b.y + b.h - 2, w: b.w, h: 2), color: c)
            framebuffer.fillRect(LunaRectI(x: b.x, y: b.y, w: 2, h: b.h), color: c)
            framebuffer.fillRect(LunaRectI(x: b.x + b.w - 2, y: b.y, w: 2, h: b.h), color: c)
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
        let firstVisibleLine = activeViewState.viewport.firstVisibleLine
        for index in 0..<rows {
            guard let line = document[line: index] else { continue }
            let y = top + 10 + index * 6
            let length = min(usableWidth, max(2, line.text.count * 2))
            framebuffer.fillRect(
                LunaRectI(x: left + 10, y: y, w: length, h: 2),
                color: index == firstVisibleLine
                    ? accent
                    : LunaRender.LunaRGBA8(r: 55, g: 58, b: 68)
            )
        }
    }

    public static let demoText = """
    // Moth Text M2.2A
    // Two pane-bound editor views share one file document while retaining
    // independent caret, selection, wrapping, and viewport state.

    import MothTextCore
    import MothEditor

    let buffer = MothInMemorySourceBuffer(text: "hello, Luna")
    var primary = MothEditorViewState(bufferID: buffer.id)
    var secondary = MothEditorViewState(
        bufferID: buffer.id,
        firstVisibleLine: 24
    )

    MothEditorTransactions.insert("!", in: buffer, view: &primary)
    // Resize the divider: each pane rewraps inside its own content bounds.
    """
}
