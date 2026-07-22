// SPDX-License-Identifier: MPL-2.0
//
// MothApplicationShellScene.swift
//
// Luna-rendered Moth editor slice backed by one real Moth-owned file document.
// Luna owns pane geometry, wrapping, clipping, hit testing, and platform input.
// Moth owns the document, history, transactions, dirty state, and independent
// editor-view state.

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
    public var historyStatus: MothHistoryStatus { document.history.status() }
    public var unicodeTextDiagnostics: MothUnicodeTextDiagnostics { MothUnicodeTextPainter.diagnostics }
    public var wantsContinuousRendering: Bool { textSelectionInteractionState.wantsContinuousUpdates }
    public var cursorIntent: LunaCursorIntent { currentCursorIntent }
    public var wantsPointerCapture: Bool {
        paneInteractionState.wantsPointerCapture || textSelectionInteractionState.wantsPointerCapture
    }
    public var bufferSnapshot: MothSourceBufferSnapshot { buffer.snapshot() }

    public mutating func openDocument(at url: URL) throws {
        document.history.breakCoalescing()
        install(document: try documentController.open(url: url))
        statusMessage = "Opened \(document.snapshot().displayPath)"
    }

    @discardableResult
    public mutating func saveDocument() throws -> MothDocumentSnapshot {
        let saved = try documentController.save(document)
        statusMessage = "Saved \(saved.displayPath) — Undo history preserved"
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
        statusMessage = "Saved \(saved.displayPath) — Undo history preserved"
        return saved
    }

    public mutating func hasExternalFileChange() throws -> Bool {
        try documentController.hasExternalChange(document)
    }

    public mutating func requestApplicationTermination() -> Bool {
        document.history.breakCoalescing()
        return prepareToReplaceOrCloseCurrentDocument(source: "window.close")
    }

    @discardableResult
    public mutating func undoDocument() -> MothHistoryActionResult? {
        textSelectionInteractionState.cancel()
        paneInteractionState.cancelDrag()
        var views = [primaryView, secondaryView]
        guard let result = document.history.undo(in: buffer, views: &views) else {
            statusMessage = "Nothing to Undo"
            return nil
        }
        restoreSceneViews(from: views)
        statusMessage = "Undo: \(result.displayName)"
        ensureActiveCaretVisible()
        return result
    }

    @discardableResult
    public mutating func redoDocument() -> MothHistoryActionResult? {
        textSelectionInteractionState.cancel()
        paneInteractionState.cancelDrag()
        var views = [primaryView, secondaryView]
        guard let result = document.history.redo(in: buffer, views: &views) else {
            statusMessage = "Nothing to Redo"
            return nil
        }
        restoreSceneViews(from: views)
        statusMessage = "Redo: \(result.displayName)"
        ensureActiveCaretVisible()
        return result
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
            document.history.breakCoalescing()
            currentCursorIntent = .arrow
            statusMessage = "Pointer selection/resize cancelled after capture loss"
            return LunaFrameInvalidationSet(.input)

        case .pointer(let pointer):
            if pointer.phase == .down { document.history.breakCoalescing() }
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
            if let result = performActiveInsert(textInput.text) {
                statusMessage = result.displayName
            }
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

        let ownsDividerGesture = wasDraggingDivider
            || paneInteraction.isDraggingDivider
            || paneResult.resizedSplitID != nil
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
        statusMessage = "\(gesture) in \(target.paneID.rawValue): bytes=\(selectedBytes)"
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
        statusMessage = "Edge autoscroll in \(target.paneID.rawValue)"
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
            if let result = performActiveDeleteBackward() {
                statusMessage = result.displayName
            }
            ensureActiveCaretVisible()

        case .delete:
            if let result = performActiveDeleteForward() {
                statusMessage = result.displayName
            }
            ensureActiveCaretVisible()

        case .enter:
            if let result = performActiveInsert("\n") {
                statusMessage = result.displayName
            }
            ensureActiveCaretVisible()

        case .arrowLeft:
            document.history.breakCoalescing()
            mutateActiveView { view in
                view.moveCaretHorizontally(
                    .backward,
                    in: snapshot.text,
                    extendingSelection: event.modifiers.shift
                )
                _ = view.synchronize(with: snapshot)
            }
            ensureActiveCaretVisible()

        case .arrowRight:
            document.history.breakCoalescing()
            mutateActiveView { view in
                view.moveCaretHorizontally(
                    .forward,
                    in: snapshot.text,
                    extendingSelection: event.modifiers.shift
                )
                _ = view.synchronize(with: snapshot)
            }
            ensureActiveCaretVisible()

        case .home:
            document.history.breakCoalescing()
            moveActiveCaretToLineBoundary(end: false, extendingSelection: event.modifiers.shift)

        case .end:
            document.history.breakCoalescing()
            moveActiveCaretToLineBoundary(end: true, extendingSelection: event.modifiers.shift)

        case .arrowUp:
            document.history.breakCoalescing()
            moveActiveCaretVertically(by: -1, extendingSelection: event.modifiers.shift)

        case .arrowDown:
            document.history.breakCoalescing()
            moveActiveCaretVertically(by: 1, extendingSelection: event.modifiers.shift)

        case .pageUp:
            document.history.breakCoalescing()
            scrollActivePane(byVisualRows: -12)

        case .pageDown:
            document.history.breakCoalescing()
            scrollActivePane(byVisualRows: 12)

        default:
            break
        }
    }

    private mutating func handleApplicationShortcut(_ event: LunaKeyboardEvent) -> Bool {
        guard event.modifiers.control || event.modifiers.command else { return false }

        if event.key == .tab {
            document.history.breakCoalescing()
            _ = paneWorkspace.traverse(event.modifiers.shift ? .previous : .next, layout: paneLayout())
            return true
        }

        guard case .other(let rawKey) = event.key else { return false }
        let key = rawKey.lowercased()

        switch key {
        case "z":
            suppressedTextInput = key
            if event.modifiers.shift {
                _ = redoDocument()
            } else {
                _ = undoDocument()
            }
            return true
        case "y":
            suppressedTextInput = key
            _ = redoDocument()
            return true
        case "o":
            suppressedTextInput = key
            document.history.breakCoalescing()
            requestOpenDocument()
            return true
        case "s":
            suppressedTextInput = key
            document.history.breakCoalescing()
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

    private mutating func performActiveInsert(_ text: String) -> MothHistoryActionResult? {
        if paneWorkspace.activePaneID == Self.secondaryPaneID {
            var others = [primaryView]
            let result = document.history.insert(
                text,
                in: buffer,
                originView: &secondaryView,
                otherViews: &others
            )
            primaryView = others[0]
            return result
        }
        var others = [secondaryView]
        let result = document.history.insert(
            text,
            in: buffer,
            originView: &primaryView,
            otherViews: &others
        )
        secondaryView = others[0]
        return result
    }

    private mutating func performActiveDeleteBackward() -> MothHistoryActionResult? {
        if paneWorkspace.activePaneID == Self.secondaryPaneID {
            var others = [primaryView]
            let result = document.history.deleteBackward(
                in: buffer,
                originView: &secondaryView,
                otherViews: &others
            )
            primaryView = others[0]
            return result
        }
        var others = [secondaryView]
        let result = document.history.deleteBackward(
            in: buffer,
            originView: &primaryView,
            otherViews: &others
        )
        secondaryView = others[0]
        return result
    }

    private mutating func performActiveDeleteForward() -> MothHistoryActionResult? {
        if paneWorkspace.activePaneID == Self.secondaryPaneID {
            var others = [primaryView]
            let result = document.history.deleteForward(
                in: buffer,
                originView: &secondaryView,
                otherViews: &others
            )
            primaryView = others[0]
            return result
        }
        var others = [secondaryView]
        let result = document.history.deleteForward(
            in: buffer,
            originView: &primaryView,
            otherViews: &others
        )
        secondaryView = others[0]
        return result
    }

    private mutating func restoreSceneViews(from views: [MothEditorViewState]) {
        for view in views {
            if view.id == primaryView.id {
                primaryView = view
            } else if view.id == secondaryView.id {
                secondaryView = view
            }
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
        MothUnicodeTextPainter.draw(
            "MOTH TEXT",
            atX: 12,
            y: 9,
            color: palette.text,
            into: &framebuffer
        )
        MothUnicodeTextPainter.draw(
            "File  Edit  Selection  Find  View  Goto  Tools",
            atX: 105,
            y: 9,
            color: palette.mutedText,
            into: &framebuffer
        )

        let documentSnapshot = document.snapshot()
        let titleX: Int
        if documentSnapshot.isDirty {
            // Dirty state is explicit geometry rather than a font-dependent
            // Unicode bullet. This remains visible even if a selected font lacks
            // a particular symbol glyph.
            framebuffer.fillRect(
                LunaRectI(x: 18, y: 47, w: 5, h: 5),
                color: activeAccent
            )
            titleX = 29
        } else {
            titleX = 18
        }
        MothUnicodeTextPainter.draw(
            documentSnapshot.displayName,
            atX: titleX,
            y: 43,
            color: palette.text,
            maximumWidth: max(0, framebuffer.width - titleX - 12),
            into: &framebuffer
        )

        let snapshot = documentSnapshot.buffer
        let history = document.history.status()
        let dirty = documentSnapshot.isDirty ? "MODIFIED" : "SAVED"
        let pane = paneWorkspace.activePaneID == Self.primaryPaneID ? "PRIMARY" : "SECONDARY"
        let baseStatus = "\(documentSnapshot.encoding.displayName)   REV \(snapshot.revision.rawValue)   H\(snapshot.historyState.rawValue)   \(dirty)   U\(history.undoGroupCount)/R\(history.redoGroupCount)   \(pane)   \(statusMessage)"
        let textDiagnostics = MothUnicodeTextPainter.diagnostics
        let status = textDiagnostics.prependingWarning(to: baseStatus)
        let statusColor = textDiagnostics.isUsingFallback
            ? palette.accentStrong
            : (documentSnapshot.isDirty ? activeAccent : palette.mutedText)
        MothUnicodeTextPainter.draw(
            status,
            atX: 12,
            y: max(0, framebuffer.height - statusHeight + 5),
            color: statusColor,
            maximumWidth: max(0, framebuffer.width - 24),
            into: &framebuffer
        )
    }

    private func drawSidebar(
        framebuffer: inout LunaFramebuffer,
        sidebarWidth: Int
    ) {
        let palette = MothApplicationTheme.renderPalette
        MothUnicodeTextPainter.draw("OPEN FILES", atX: 16, y: 84, color: palette.mutedText, into: &framebuffer)
        let snapshot = document.snapshot()
        MothUnicodeTextPainter.draw(
            snapshot.displayName,
            atX: 28,
            y: 106,
            color: activeAccent,
            maximumWidth: sidebarWidth - 38,
            into: &framebuffer
        )
        MothUnicodeTextPainter.draw("DOCUMENT", atX: 16, y: 140, color: palette.mutedText, into: &framebuffer)
        MothUnicodeTextPainter.draw(snapshot.isUntitled ? "UNTITLED" : "FILE-BACKED", atX: 28, y: 162, color: palette.text, into: &framebuffer)
        MothUnicodeTextPainter.draw(snapshot.encoding.displayName, atX: 40, y: 182, color: palette.mutedText, maximumWidth: sidebarWidth - 50, into: &framebuffer)
        MothUnicodeTextPainter.draw(snapshot.displayPath, atX: 40, y: 202, color: palette.mutedText, maximumWidth: sidebarWidth - 50, into: &framebuffer)
        MothUnicodeTextPainter.draw("Ctrl+Z Undo   Ctrl+Shift+Z Redo", atX: 28, y: 234, color: palette.mutedText, maximumWidth: sidebarWidth - 38, into: &framebuffer)
        MothUnicodeTextPainter.draw("Ctrl+O Open   Ctrl+S Save", atX: 28, y: 254, color: palette.mutedText, maximumWidth: sidebarWidth - 38, into: &framebuffer)
        MothUnicodeTextPainter.draw("Ctrl+Tab switches panes", atX: 28, y: 274, color: palette.mutedText, maximumWidth: sidebarWidth - 38, into: &framebuffer)
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
            if active {
                framebuffer.fillRect(
                    LunaRectI(
                        x: frame.headerBounds.x + 8,
                        y: frame.headerBounds.y + 9,
                        w: 4,
                        h: 4
                    ),
                    color: activeAccent
                )
            }
            MothUnicodeTextPainter.draw(
                title,
                atX: frame.headerBounds.x + 18,
                y: frame.headerBounds.y + 5,
                color: active ? activeAccent : palette.mutedText,
                maximumWidth: max(0, frame.headerBounds.w - 92),
                into: &framebuffer
            )
            let scroll = view.viewport.firstVisibleVisualRow.map { "ROW \($0)" }
                ?? "LINE \(view.viewport.firstVisibleLine + 1)"
            MothUnicodeTextPainter.draw(
                scroll,
                atX: max(frame.headerBounds.x + 8, frame.headerBounds.x + frame.headerBounds.w - 72),
                y: frame.headerBounds.y + 5,
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
    // Moth Text Convergence C2
    // Two pane-bound editor views share one file document and one Moth-owned
    // Undo/Redo history while retaining independent caret, selection, wrapping,
    // and viewport state.

    import MothTextCore
    import MothEditor

    let buffer = MothInMemorySourceBuffer(text: "hello, Luna")
    var primary = MothEditorViewState(bufferID: buffer.id)
    var secondary = MothEditorViewState(
        bufferID: buffer.id,
        firstVisibleLine: 24
    )

    // Ctrl/Cmd+Z and Ctrl/Cmd+Shift+Z traverse document history.
    """
}
