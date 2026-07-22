// SPDX-License-Identifier: MPL-2.0
//
// MothApplicationShellScene.swift
//
// Luna-rendered Moth editor slice backed by one real Moth-owned file document.
// Luna owns pane geometry, wrapping, clipping, hit testing, and platform input.
// Moth owns the document, history, transactions, dirty state, and independent
// editor-view state.

import Foundation
import LunaCommands
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaTheme
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
    public private(set) var lastCommandID: LunaCommandID?
    public private(set) var lastCommandSource: String?

    private var documentController: MothDocumentController<MothLocalDocumentFileAccess>
    private var dialogService: any LunaDialogService
    private var suppressedTextInput: String?
    private var paneInteractionState: LunaPaneContainerInteractionState
    private var textSelectionInteractionState: LunaTextSelectionInteractionState
    private var currentCursorIntent: LunaCursorIntent
    private var commandRuntime: LunaCommandRuntime<MothApplicationShellScene>
    private var menuBarState: LunaMenuBarState
    private var commandPaletteState: LunaQuickPanelState?

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
        self.commandRuntime = MothCommandSystem.makeRuntime()
        self.menuBarState = LunaMenuBarState()
        self.commandPaletteState = nil
        self.lastCommandID = nil
        self.lastCommandSource = nil
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
    public var commandDescriptors: [LunaCommandDescriptor] { commandRuntime.descriptors }
    public var isMenuOpen: Bool { menuBarState.isOpen }
    public var isCommandPaletteOpen: Bool { commandPaletteState != nil }
    public var commandPaletteQuery: String? { commandPaletteState?.query }

    public func commandAvailability(
        for command: LunaCommandID,
        source: String = "programmatic"
    ) -> LunaCommandAvailability {
        commandRuntime.availability(
            for: command,
            host: self,
            context: commandContext(source: source)
        )
    }

    @discardableResult
    public mutating func executeCommand(
        _ command: LunaCommandID,
        source: String = "programmatic"
    ) -> LunaCommandExecutionResult {
        let runtime = commandRuntime
        let result = runtime.execute(
            command,
            host: &self,
            context: commandContext(source: source)
        )
        applyCommandResult(result, command: command, source: source)
        return result
    }

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
            menuBarState.close()
            commandPaletteState = nil
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
            if var palette = commandPaletteState {
                let result = palette.handleTextInput(textInput)
                commandPaletteState = palette
                if result.didConsumeEvent {
                    currentCursorIntent = .arrow
                    return LunaFrameInvalidationSet(.input)
                }
            }
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
        drawMenuSurface(into: &framebuffer)
        drawCommandPalette(into: &framebuffer)
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
        if commandPaletteState != nil || menuBarState.isOpen { return .arrow }
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
        if handleCommandPalettePointer(event) { return }
        if handleMenuPointer(event) { return }

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

    // MARK: - Command surfaces

    private func menuBar() -> LunaMenuBar {
        LunaMenuBar(
            id: LunaNodeID(rawValue: "moth.menuBar"),
            bounds: LunaRectI(
                x: 96,
                y: 0,
                w: max(0, framebufferSize.width - 96),
                h: min(30, framebufferSize.height)
            ),
            menus: commandMenus(),
            state: menuBarState,
            theme: MothApplicationTheme.theme,
            metrics: LunaMenuBarMetrics(
                barHeight: 30,
                topLevelHorizontalPadding: 9,
                dropdownMinWidth: 224,
                dropdownMaxWidth: 340,
                dropdownPadding: 5,
                rowHeight: 26,
                separatorHeight: 7,
                rowHorizontalPadding: 10,
                shortcutColumnWidth: 96,
                submenuGap: 2,
                textScale: 1,
                glyphMetrics: MothUnicodeTextPainter.editorMetrics.glyphMetrics
            )
        )
    }

    private func commandMenus() -> [LunaMenuDefinition] {
        [
            LunaMenuDefinition(
                id: "file",
                title: "File",
                items: [
                    menuItem(for: MothCommandID.newFile),
                    menuItem(for: MothCommandID.openFile),
                    .separator(id: "file.separator.save"),
                    menuItem(for: MothCommandID.save),
                    menuItem(for: MothCommandID.saveAs),
                ]
            ),
            LunaMenuDefinition(
                id: "edit",
                title: "Edit",
                items: [
                    menuItem(for: MothCommandID.undo),
                    menuItem(for: MothCommandID.redo),
                ]
            ),
            LunaMenuDefinition(
                id: "selection",
                title: "Selection",
                items: [menuItem(for: MothCommandID.selectAll)]
            ),
            LunaMenuDefinition(
                id: "find",
                title: "Find",
                items: [menuItem(for: MothCommandID.showFind)]
            ),
            LunaMenuDefinition(
                id: "view",
                title: "View",
                items: [
                    menuItem(for: MothCommandID.nextPane),
                    menuItem(for: MothCommandID.previousPane),
                ]
            ),
            LunaMenuDefinition(
                id: "goto",
                title: "Goto",
                items: [
                    LunaMenuItem(
                        id: "goto.pending",
                        title: "Goto commands arrive with M3",
                        isEnabled: false
                    ),
                ]
            ),
            LunaMenuDefinition(
                id: "tools",
                title: "Tools",
                items: [menuItem(for: MothCommandID.showCommandPalette)]
            ),
        ]
    }

    private func menuItem(for command: LunaCommandID) -> LunaMenuItem {
        let context = commandContext(source: "menu")
        guard let item = commandRuntime.surfaceItem(for: command, host: self, context: context) else {
            return LunaMenuItem(
                id: "missing.\(command.rawValue)",
                title: command.rawValue,
                isEnabled: false
            )
        }
        return .command(
            id: item.id.rawValue,
            title: item.title,
            command: item.id,
            keyEquivalent: item.keyEquivalent,
            isEnabled: item.isEnabled,
            isChecked: item.isChecked,
            accessibilityLabel: item.disabledReason.map { "\(item.accessibilityLabel). \($0)" }
                ?? item.accessibilityLabel
        )
    }

    private mutating func handleMenuPointer(_ event: LunaPointerEvent) -> Bool {
        let bar = menuBar()
        var state = menuBarState
        let result = bar.handlePointerEvent(event, state: &state)
        menuBarState = state
        guard result.didConsumeEvent else { return false }
        currentCursorIntent = .arrow
        if let command = result.requestedCommand {
            _ = executeCommand(command, source: "menu")
        }
        return true
    }

    private mutating func handleMenuKeyboard(_ event: LunaKeyboardEvent) -> Bool {
        guard menuBarState.isOpen else { return false }
        let bar = menuBar()
        var state = menuBarState
        let result = bar.handleKeyboardEvent(event, state: &state)
        menuBarState = state
        guard result.didConsumeEvent else { return false }
        currentCursorIntent = .arrow
        if let command = result.requestedCommand {
            _ = executeCommand(command, source: "menu")
        }
        return true
    }

    private mutating func openCommandPalette() {
        menuBarState.close()
        commandPaletteState = LunaQuickPanelState(items: commandPaletteItems())
        currentCursorIntent = .arrow
    }

    private func commandPaletteItems() -> [LunaQuickPanelItem] {
        let context = commandContext(source: "palette")
        return commandRuntime.registry.paletteVisible.compactMap { descriptor in
            let availability = commandRuntime.availability(
                for: descriptor.id,
                host: self,
                context: context
            )
            guard availability.isVisible else { return nil }
            let path = descriptor.menuPath.joined(separator: " › ")
            let subtitleParts = [
                path.isEmpty ? nil : path,
                availability.disabledReason,
            ].compactMap { $0 }
            return LunaQuickPanelItem(
                id: LunaNodeID(rawValue: "moth.command.\(descriptor.id.rawValue)"),
                title: availability.titleOverride ?? descriptor.title,
                subtitle: subtitleParts.isEmpty ? descriptor.id.rawValue : subtitleParts.joined(separator: " — "),
                command: descriptor.id,
                isEnabled: availability.isEnabled
            )
        }
    }

    private func commandPalette() -> LunaQuickPanel? {
        guard let commandPaletteState else { return nil }
        return LunaQuickPanel(
            id: LunaNodeID(rawValue: "moth.commandPalette"),
            bounds: LunaRectI(
                x: 0,
                y: 0,
                w: framebufferSize.width,
                h: framebufferSize.height
            ),
            title: "Moth Command Palette",
            placeholder: "Type a command…",
            state: commandPaletteState,
            theme: MothApplicationTheme.theme,
            metrics: LunaQuickPanelMetrics(
                maxPanelWidth: 680,
                minPanelWidth: 300,
                topMargin: 64,
                sideMargin: 18,
                panelPadding: 10,
                titleHeight: 26,
                inputHeight: 30,
                rowHeight: 36,
                rowGap: 2,
                maxVisibleRows: 10,
                textScale: 1,
                titleScale: 1,
                glyphMetrics: MothUnicodeTextPainter.editorMetrics.glyphMetrics
            )
        )
    }

    private mutating func handleCommandPaletteKeyboard(_ event: LunaKeyboardEvent) -> Bool {
        guard var state = commandPaletteState else { return false }
        let result = state.handleKeyboardEvent(event)
        guard result.didConsumeEvent else {
            commandPaletteState = state
            return false
        }
        currentCursorIntent = .arrow

        if let command = result.requestedCommand {
            let availability = commandRuntime.availability(
                for: command,
                host: self,
                context: commandContext(source: "palette")
            )
            guard availability.isEnabled else {
                commandPaletteState = state
                lastCommandID = command
                lastCommandSource = "palette"
                statusMessage = availability.disabledReason ?? "Command unavailable"
                return true
            }
            commandPaletteState = nil
            _ = executeCommand(command, source: "palette")
            return true
        }

        commandPaletteState = result.didDismiss ? nil : state
        return true
    }

    private mutating func handleCommandPalettePointer(_ event: LunaPointerEvent) -> Bool {
        guard var state = commandPaletteState, let panel = commandPalette() else { return false }
        currentCursorIntent = .arrow
        guard event.phase == .down else { return true }

        let layout = panel.layout()
        if let row = layout.rows.first(where: { $0.bounds.contains(x: event.location.x, y: event.location.y) }) {
            let result = state.selectOriginalIndex(row.match.originalIndex)
            guard let command = result.requestedCommand else {
                commandPaletteState = result.didDismiss ? nil : state
                return true
            }

            let availability = commandRuntime.availability(
                for: command,
                host: self,
                context: commandContext(source: "palette")
            )
            if availability.isEnabled {
                commandPaletteState = nil
                _ = executeCommand(command, source: "palette")
            } else {
                commandPaletteState = state
                lastCommandID = command
                lastCommandSource = "palette"
                statusMessage = availability.disabledReason ?? "Command unavailable"
            }
            return true
        }

        if !layout.panelBounds.contains(x: event.location.x, y: event.location.y) {
            commandPaletteState = nil
            statusMessage = "Command Palette dismissed"
        }
        return true
    }

    // MARK: - Editing and commands

    private mutating func handleKeyboard(_ event: LunaKeyboardEvent) {
        if handleCommandPaletteKeyboard(event) { return }
        if handleMenuKeyboard(event) { return }
        if handleCommandShortcut(event) { return }
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

    private mutating func handleCommandShortcut(_ event: LunaKeyboardEvent) -> Bool {
        let context = commandContext(source: "keyboard")
        let candidates = commandRuntime.keyBindings.commands(
            matching: event.lunaCommandKeyStroke,
            context: context
        )
        guard let command = candidates.first else { return false }

        suppressedTextInput = event.lunaShortcutTextInputSuppressionCandidate
        let availability = commandRuntime.availability(for: command, host: self, context: context)
        guard availability.isVisible && availability.isEnabled else {
            lastCommandID = command
            lastCommandSource = "keyboard"
            statusMessage = availability.disabledReason ?? "Command unavailable"
            return true
        }

        _ = executeCommand(command, source: "keyboard")
        return true
    }

    func registeredCommandAvailability(
        _ command: LunaCommandID,
        context: LunaCommandContext
    ) -> LunaCommandAvailability {
        let snapshot = document.snapshot()
        let history = document.history.status()

        switch command {
        case MothCommandID.newFile, MothCommandID.openFile,
             MothCommandID.saveAs, MothCommandID.nextPane,
             MothCommandID.previousPane, MothCommandID.showCommandPalette:
            return .enabled
        case MothCommandID.save:
            return snapshot.isUntitled || snapshot.isDirty
                ? .enabled
                : .disabled("Document is already saved")
        case MothCommandID.undo:
            return history.canUndo ? .enabled : .disabled("Nothing to Undo")
        case MothCommandID.redo:
            return history.canRedo ? .enabled : .disabled("Nothing to Redo")
        case MothCommandID.selectAll:
            return snapshot.buffer.utf8Count > 0
                ? .enabled
                : .disabled("Document is empty")
        case MothCommandID.showFind:
            return .disabled("Visible Find/Replace is planned for M2.2B2")
        default:
            return .disabled("Unknown Moth command")
        }
    }

    mutating func performRegisteredCommand(
        _ command: LunaCommandID,
        context: LunaCommandContext
    ) -> LunaCommandExecutionResult {
        document.history.breakCoalescing()
        textSelectionInteractionState.cancel()
        paneInteractionState.cancelDrag()

        switch command {
        case MothCommandID.newFile:
            return createNewUntitledDocument()
                ? .handled("New untitled document")
                : .unhandled(statusMessage)
        case MothCommandID.openFile:
            requestOpenDocument()
            return .handled(statusMessage)
        case MothCommandID.save:
            if document.snapshot().isUntitled {
                return requestSaveDocumentAs()
                    ? .handled(statusMessage)
                    : .unhandled(statusMessage)
            }
            do {
                _ = try saveDocument()
                return .handled(statusMessage)
            } catch {
                return .unhandled(error.localizedDescription)
            }
        case MothCommandID.saveAs:
            return requestSaveDocumentAs()
                ? .handled(statusMessage)
                : .unhandled(statusMessage)
        case MothCommandID.undo:
            guard let result = undoDocument() else { return .unhandled(statusMessage) }
            return .handled("Undo: \(result.displayName)")
        case MothCommandID.redo:
            guard let result = redoDocument() else { return .unhandled(statusMessage) }
            return .handled("Redo: \(result.displayName)")
        case MothCommandID.selectAll:
            selectAllInActiveView()
            return .handled("Selected entire document")
        case MothCommandID.nextPane:
            _ = paneWorkspace.traverse(.next, layout: paneLayout())
            return .handled("Active pane: \(paneWorkspace.activePaneID.rawValue)")
        case MothCommandID.previousPane:
            _ = paneWorkspace.traverse(.previous, layout: paneLayout())
            return .handled("Active pane: \(paneWorkspace.activePaneID.rawValue)")
        case MothCommandID.showCommandPalette:
            openCommandPalette()
            return .handled("Command Palette")
        case MothCommandID.showFind:
            return .unhandled("Visible Find/Replace is planned for M2.2B2")
        default:
            return .unhandled("Unknown Moth command: \(command.rawValue)")
        }
    }

    private func commandContext(source: String) -> LunaCommandContext {
        LunaCommandContext(
            focusedSurface: commandPaletteState == nil ? "editor" : "commandPalette",
            activeDocumentID: document.snapshot().id.description,
            source: source,
            attributes: [
                LunaCommandContextAttributeKey.activePaneID: paneWorkspace.activePaneID.rawValue,
            ]
        )
    }

    private mutating func applyCommandResult(
        _ result: LunaCommandExecutionResult,
        command: LunaCommandID,
        source: String
    ) {
        lastCommandID = command
        lastCommandSource = source
        if let message = result.statusMessage {
            statusMessage = message
        }
        if let followUp = result.followUpCommand, followUp != command {
            _ = executeCommand(followUp, source: "followUp")
        }
    }

    private mutating func createNewUntitledDocument() -> Bool {
        guard prepareToReplaceOrCloseCurrentDocument(source: "moth.command.new") else {
            return false
        }
        install(document: MothFileDocument(untitledText: "", displayName: "untitled.txt"))
        menuBarState.close()
        commandPaletteState = nil
        currentCursorIntent = .arrow
        statusMessage = "New untitled document"
        return true
    }

    private mutating func selectAllInActiveView() {
        let count = buffer.snapshot().utf8Count
        mutateActiveView { view in
            view.setSelection(
                anchor: .zero,
                focus: MothTextOffset(rawValue: count)
            )
            view.preferredUTF8Column = nil
        }
        ensureActiveCaretVisible()
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

    private func drawMenuSurface(into framebuffer: inout LunaFramebuffer) {
        let bar = menuBar()
        var displayList = LunaDisplayList()
        bar.buildDisplayList(into: &displayList)
        LunaCPURenderer().render(displayList: displayList, into: &framebuffer)

        let layout = bar.layout()
        let theme = MothApplicationTheme.theme
        for top in layout.topLevelFrames {
            let isActive = bar.state.activeMenuIndex == top.index
            let color = isActive
                ? theme.ui.chrome.menuBarActiveForeground.asRenderColor
                : theme.ui.chrome.menuBarForeground.asRenderColor
            MothUnicodeTextPainter.draw(
                top.title,
                atX: top.bounds.x + 8,
                y: top.bounds.y + 9,
                color: color,
                maximumWidth: max(0, top.bounds.w - 16),
                into: &framebuffer
            )
        }

        for dropdown in layout.dropdowns {
            for row in dropdown.rows where !row.item.isSeparator {
                let highlighted = bar.state.highlightedPath == row.path
                let titleColor: LunaRender.LunaRGBA8
                if !row.item.isEnabled {
                    titleColor = theme.ui.menu.rowDisabledForeground.asRenderColor
                } else if highlighted {
                    titleColor = theme.ui.menu.rowHoveredForeground.asRenderColor
                } else {
                    titleColor = theme.ui.menu.rowForeground.asRenderColor
                }
                let shortcutColor = row.item.isEnabled
                    ? theme.ui.menu.shortcutForeground.asRenderColor
                    : theme.ui.menu.rowDisabledForeground.asRenderColor

                if row.item.isChecked {
                    MothUnicodeTextPainter.draw(
                        "*",
                        atX: row.bounds.x + 8,
                        y: row.titleBounds.y + 5,
                        color: theme.ui.menu.checkedMark.asRenderColor,
                        into: &framebuffer
                    )
                }
                MothUnicodeTextPainter.draw(
                    row.item.title,
                    atX: row.titleBounds.x,
                    y: row.titleBounds.y + 5,
                    color: titleColor,
                    maximumWidth: row.titleBounds.w,
                    into: &framebuffer
                )
                if let shortcut = row.item.keyEquivalent?.lunaMenuDisplayString {
                    MothUnicodeTextPainter.draw(
                        shortcut,
                        atX: row.shortcutBounds.x,
                        y: row.shortcutBounds.y + 5,
                        color: shortcutColor,
                        maximumWidth: row.shortcutBounds.w,
                        into: &framebuffer
                    )
                }
            }
        }
    }

    private func drawCommandPalette(into framebuffer: inout LunaFramebuffer) {
        guard let panel = commandPalette() else { return }
        var displayList = LunaDisplayList()
        panel.buildDisplayList(into: &displayList)
        LunaCPURenderer().render(displayList: displayList, into: &framebuffer)

        let theme = MothApplicationTheme.theme
        let text = panel.textLayout()
        MothUnicodeTextPainter.draw(
            text.title.text,
            atX: text.title.bounds.x,
            y: text.title.bounds.y + 5,
            color: theme.ui.panel.titleForeground.asRenderColor,
            maximumWidth: text.title.bounds.w,
            into: &framebuffer
        )
        let queryColor = panel.state.query.isEmpty
            ? theme.ui.textField.placeholderForeground.asRenderColor
            : theme.ui.textField.foreground.asRenderColor
        MothUnicodeTextPainter.draw(
            text.query.text,
            atX: text.query.bounds.x,
            y: text.query.bounds.y + 5,
            color: queryColor,
            maximumWidth: text.query.bounds.w,
            into: &framebuffer
        )

        let rowItems = Dictionary(uniqueKeysWithValues: panel.layout().rows.map { ($0.nodeID, $0.match.item) })
        for row in text.rows {
            let item = rowItems[row.nodeID]
            let enabled = item?.isEnabled ?? true
            let titleColor: LunaRender.LunaRGBA8
            let subtitleColor: LunaRender.LunaRGBA8
            if !enabled {
                titleColor = theme.ui.menu.rowDisabledForeground.asRenderColor
                subtitleColor = theme.ui.menu.rowDisabledForeground.asRenderColor
            } else if row.isSelected {
                titleColor = theme.ui.menu.rowHoveredForeground.asRenderColor
                subtitleColor = theme.ui.menu.rowHoveredForeground.asRenderColor
            } else {
                titleColor = theme.ui.menu.rowForeground.asRenderColor
                subtitleColor = theme.ui.menu.rowMutedForeground.asRenderColor
            }
            MothUnicodeTextPainter.draw(
                row.title.text,
                atX: row.title.bounds.x,
                y: row.title.bounds.y + 3,
                color: titleColor,
                maximumWidth: row.title.bounds.w,
                into: &framebuffer
            )
            if let subtitle = row.subtitle {
                MothUnicodeTextPainter.draw(
                    subtitle.text,
                    atX: subtitle.bounds.x,
                    y: subtitle.bounds.y + 2,
                    color: subtitleColor,
                    maximumWidth: subtitle.bounds.w,
                    into: &framebuffer
                )
            }
        }
        if let empty = text.emptyState {
            MothUnicodeTextPainter.draw(
                empty.text,
                atX: empty.bounds.x,
                y: empty.bounds.y + 5,
                color: theme.ui.panel.mutedForeground.asRenderColor,
                maximumWidth: empty.bounds.w,
                into: &framebuffer
            )
        }
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
        MothUnicodeTextPainter.draw("Ctrl+N New   Ctrl+O Open", atX: 28, y: 234, color: palette.mutedText, maximumWidth: sidebarWidth - 38, into: &framebuffer)
        MothUnicodeTextPainter.draw("Ctrl+S Save   Ctrl+A Select All", atX: 28, y: 254, color: palette.mutedText, maximumWidth: sidebarWidth - 38, into: &framebuffer)
        MothUnicodeTextPainter.draw("Ctrl+Shift+P Command Palette", atX: 28, y: 274, color: palette.mutedText, maximumWidth: sidebarWidth - 38, into: &framebuffer)
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
    // Moth Text M2.2B1
    // Keyboard shortcuts, menus, and the command palette now route through one
    // Moth-owned command authority built on Luna's reusable command runtime.

    import MothTextCore
    import MothEditor

    let buffer = MothInMemorySourceBuffer(text: "hello, Luna")
    var primary = MothEditorViewState(bufferID: buffer.id)
    var secondary = MothEditorViewState(
        bufferID: buffer.id,
        firstVisibleLine: 24
    )

    // Ctrl/Cmd+N creates a protected new document; Ctrl/Cmd+Shift+P opens the palette.
    """
}
