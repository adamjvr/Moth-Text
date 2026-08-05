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
    public private(set) var hostFrameTimingStats: LunaFrameTimingStats
    public private(set) var hostInputStats: LunaInputCoalescingStats
    public private(set) var latestFrameInvalidations: LunaFrameInvalidationSet
    public private(set) var latestFrameRenderReport: LunaFrameRenderReport?
    public private(set) var documentSheets = MothDocumentSheetCollection()

    private var documentController: MothDocumentController<MothLocalDocumentFileAccess>
    private var dialogService: any LunaDialogService
    private var clipboardService: any LunaClipboardService
    private var findPanelState: LunaFindPanelState
    private var isFindPanelPresented: Bool
    private var findPanelReturnPaneID: LunaPaneID
    private var findPanelPointerField: LunaFindPanelField?
    private var suppressedTextInput: String?
    private var paneInteractionState: LunaPaneContainerInteractionState
    private var textSelectionInteractionState: LunaTextSelectionInteractionState
    private var scrollbarInteractionState: LunaStaticTextScrollbarInteractionState
    private var currentCursorIntent: LunaCursorIntent
    private var commandRuntime: LunaCommandRuntime<MothApplicationShellScene>
    private var menuBarState: LunaMenuBarState
    private var commandPaletteState: LunaQuickPanelState?
    private var documentShellState = LunaEditorShellState(
        isSidebarVisible: false,
        sidebarWidth: 0
    )
    private var openFilesShellState = LunaEditorShellState(
        isSidebarVisible: true,
        sidebarWidth: 236
    )
    private var pendingFrameRenderReport: LunaFrameRenderReport?
    private var staticFrameCache: MothApplicationStaticFrameCache?
    private var paneGeometryGeneration: UInt64
    private var paneViewGeneration: UInt64
    private let viewportPresentationStore: MothDocumentViewportPresentationStore
    private let paneInteractionSnapshotStore: MothPaneInteractionSnapshotStore
    private let runtimeAttributionRecorder: MothRuntimeWorkAttributionRecorder

    public init(
        initialSize: LunaSizeI = LunaSizeI(width: 1100, height: 720),
        initialText: String = Self.demoText,
        dialogService: any LunaDialogService = LunaNoOpDialogService(),
        clipboardService: any LunaClipboardService = LunaUnavailableClipboardService()
    ) {
        self.init(
            initialSize: initialSize,
            document: MothFileDocument(
                untitledText: initialText,
                displayName: "untitled.txt"
            ),
            dialogService: dialogService,
            clipboardService: clipboardService
        )
    }

    public init(
        initialSize: LunaSizeI = LunaSizeI(width: 1100, height: 720),
        document: MothFileDocument,
        dialogService: any LunaDialogService = LunaNoOpDialogService(),
        clipboardService: any LunaClipboardService = LunaUnavailableClipboardService()
    ) {
        self.framebufferSize = initialSize
        self.pointerAccentIsActive = false
        self.keyboardEventCount = 0
        self.document = document
        self.documentController = MothDocumentController(fileAccess: MothLocalDocumentFileAccess())
        self.dialogService = dialogService
        self.clipboardService = clipboardService
        self.findPanelState = LunaFindPanelState()
        self.isFindPanelPresented = false
        self.findPanelReturnPaneID = Self.primaryPaneID
        self.findPanelPointerField = nil
        self.suppressedTextInput = nil
        self.paneInteractionState = LunaPaneContainerInteractionState()
        self.textSelectionInteractionState = LunaTextSelectionInteractionState()
        self.scrollbarInteractionState = LunaStaticTextScrollbarInteractionState()
        self.currentCursorIntent = .arrow
        self.commandRuntime = MothCommandSystem.makeRuntime()
        self.menuBarState = LunaMenuBarState()
        self.commandPaletteState = nil
        self.lastCommandID = nil
        self.lastCommandSource = nil
        self.hostFrameTimingStats = LunaFrameTimingStats()
        self.hostInputStats = LunaInputCoalescingStats()
        self.latestFrameInvalidations = LunaFrameInvalidationSet(.initial)
        self.latestFrameRenderReport = nil
        self.pendingFrameRenderReport = nil
        self.staticFrameCache = nil
        self.paneGeometryGeneration = 0
        self.paneViewGeneration = 0
        self.viewportPresentationStore = MothDocumentViewportPresentationStore()
        self.paneInteractionSnapshotStore = MothPaneInteractionSnapshotStore()
        self.runtimeAttributionRecorder = MothRuntimeWorkAttributionRecorder()
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
        let initialSheetID = documentSheets.installInitial(
            document: self.document,
            primaryView: primaryView,
            secondaryView: secondaryView,
            findPanelState: findPanelState
        )
        documentShellState.tabStrip.activeTabID = LunaShellTabID(
            rawValue: initialSheetID.rawValue
        )
    }

    public var buffer: MothInMemorySourceBuffer { document.buffer }
    public var documentSnapshot: MothDocumentSnapshot { document.snapshot() }
    public var historyStatus: MothHistoryStatus { document.history.status() }
    public var unicodeTextDiagnostics: MothUnicodeTextDiagnostics { MothUnicodeTextPainter.diagnostics }
    public var unicodeTextPerformance: MothUnicodeTextPerformanceSnapshot {
        MothUnicodeTextPainter.performanceSnapshot
    }

    public var runtimeWorkAttribution: MothRuntimeWorkAttributionSnapshot {
        runtimeAttributionRecorder.snapshot
    }

    public func flushRuntimeWorkAttributionIfRequested() throws {
        try runtimeAttributionRecorder.flushIfRequested()
    }

    public var runtimePerformanceDiagnostics: String {
        let performance = MothUnicodeTextPainter.performanceSnapshot
        return String(
            format: "latency %.2f ms | %@ | %@ | %@",
            hostFrameTimingStats.movingAverageInputToPresentMilliseconds,
            hostInputStats.statusText,
            performance.compactStatusText,
            hostFrameTimingStats.renderPathStatusText
        )
    }

    public mutating func updateHostRuntimeDiagnostics(
        timingStats: LunaFrameTimingStats,
        inputStats: LunaInputCoalescingStats,
        invalidations: LunaFrameInvalidationSet = LunaFrameInvalidationSet()
    ) {
        hostFrameTimingStats = timingStats
        hostInputStats = inputStats
        latestFrameInvalidations = invalidations
    }

    public mutating func takeFrameRenderReport() -> LunaFrameRenderReport? {
        let report = pendingFrameRenderReport
        pendingFrameRenderReport = nil
        return report
    }

    public var wantsContinuousRendering: Bool { textSelectionInteractionState.wantsContinuousUpdates }
    public var cursorIntent: LunaCursorIntent { currentCursorIntent }
    public var wantsPointerCapture: Bool {
        paneInteractionState.wantsPointerCapture
            || textSelectionInteractionState.wantsPointerCapture
            || scrollbarInteractionState.isDragging
    }
    public var bufferSnapshot: MothSourceBufferSnapshot { buffer.snapshot() }
    public var commandDescriptors: [LunaCommandDescriptor] { commandRuntime.descriptors }
    public var isMenuOpen: Bool { menuBarState.isOpen }
    public var isCommandPaletteOpen: Bool { commandPaletteState != nil }
    public var commandPaletteQuery: String? { commandPaletteState?.query }
    public var isFindPanelOpen: Bool { isFindPanelPresented }
    public var findPanelSnapshot: LunaFindPanelState { findPanelState }
    public var clipboardIsAvailable: Bool { clipboardService.isAvailable }
    public var activeDocumentSheetID: MothDocumentSheetID? {
        documentSheets.activeSheetID
    }
    public var documentSheetCount: Int { documentSheets.count }
    public var documentSheetIDs: [MothDocumentSheetID] { documentSheets.ids }

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
        let canonicalURL = canonicalFileURL(url)
        captureActiveDocumentSheet()
        if let existing = documentSheets.sheets.first(where: { sheet in
            guard let fileURL = sheet.document.snapshot().fileURL else {
                return false
            }
            return canonicalFileURL(fileURL) == canonicalURL
        }) {
            _ = loadDocumentSheet(existing.id)
            statusMessage = "Already open: \(document.snapshot().displayPath)"
            return
        }

        let opened = try documentController.open(url: canonicalURL)
        _ = appendDocumentSheet(opened)
        statusMessage = "Opened \(document.snapshot().displayPath) in a new tab"
    }

    @discardableResult
    public mutating func saveDocument() throws -> MothDocumentSnapshot {
        let saved = try documentController.save(document)
        captureActiveDocumentSheet()
        synchronizeDocumentTabState()
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
        captureActiveDocumentSheet()
        synchronizeDocumentTabState()
        statusMessage = "Saved \(saved.displayPath) — Undo history preserved"
        return saved
    }

    public mutating func hasExternalFileChange() throws -> Bool {
        try documentController.hasExternalChange(document)
    }

    public mutating func requestApplicationTermination() -> Bool {
        captureActiveDocumentSheet()
        let originalID = documentSheets.activeSheetID
        for id in documentSheets.ids {
            guard loadDocumentSheet(id) else { continue }
            document.history.breakCoalescing()
            if !prepareToReplaceOrCloseCurrentDocument(source: "window.close") {
                return false
            }
            captureActiveDocumentSheet()
        }
        if let originalID, documentSheets.sheet(with: originalID) != nil {
            _ = loadDocumentSheet(originalID)
        }
        return true
    }

    @discardableResult
    public mutating func undoDocument() -> MothHistoryActionResult? {
        textSelectionInteractionState.cancel()
        paneInteractionState.cancelDrag()
        scrollbarInteractionState.cancel()
        var views = [primaryView, secondaryView]
        guard let result = document.history.undo(in: buffer, views: &views) else {
            statusMessage = "Nothing to Undo"
            return nil
        }
        restoreSceneViews(from: views)
        refreshFindPanelAfterDocumentMutation()
        statusMessage = "Undo: \(result.displayName)"
        ensureActiveCaretVisible()
        return result
    }

    @discardableResult
    public mutating func redoDocument() -> MothHistoryActionResult? {
        textSelectionInteractionState.cancel()
        paneInteractionState.cancelDrag()
        scrollbarInteractionState.cancel()
        var views = [primaryView, secondaryView]
        guard let result = document.history.redo(in: buffer, views: &views) else {
            statusMessage = "Nothing to Redo"
            return nil
        }
        restoreSceneViews(from: views)
        refreshFindPanelAfterDocumentMutation()
        statusMessage = "Redo: \(result.displayName)"
        ensureActiveCaretVisible()
        return result
    }

    public mutating func handleHostEvent(
        _ event: LunaHostInputEvent,
        framebufferSize: LunaSizeI
    ) -> LunaFrameInvalidationSet {
        self.framebufferSize = framebufferSize
        let invalidations: LunaFrameInvalidationSet

        switch event {
        case .quit:
            invalidations = LunaFrameInvalidationSet()

        case .windowResized:
            paneGeometryGeneration &+= 1
            paneInteractionSnapshotStore.removeAll()
            resetWrappedScrollAnchors()
            staticFrameCache = nil
            invalidations = LunaFrameInvalidationSet(.windowResized)

        case .pointerCaptureLost:
            paneInteractionState.cancelDrag()
            paneInteractionState.hoveredSplitID = nil
            textSelectionInteractionState.cancel()
            scrollbarInteractionState.cancel()
            document.history.breakCoalescing()
            currentCursorIntent = .arrow
            menuBarState.close()
            commandPaletteState = nil
            findPanelPointerField = nil
            statusMessage = "Pointer selection, scrollbar, or resize gesture cancelled after capture loss"
            invalidations = LunaFrameInvalidationSet(.input)

        case .pointer(let pointer):
            if pointer.phase == .down { document.history.breakCoalescing() }
            invalidations = handlePointer(pointer)

        case .scroll(let scroll):
            invalidations = handleScroll(scroll)
                ? LunaFrameInvalidationSet(.scrollChanged)
                : LunaFrameInvalidationSet()

        case .keyboard(let keyboard):
            keyboardEventCount &+= 1
            invalidations = handleKeyboardWithMeasuredInvalidation(keyboard)

        case .textInput(let textInput):
            if textInput.text.isEmpty {
                invalidations = LunaFrameInvalidationSet()
            } else if let suppressedTextInput,
                      textInput.text.lowercased() == suppressedTextInput {
                self.suppressedTextInput = nil
                invalidations = LunaFrameInvalidationSet(.input)
            } else {
                suppressedTextInput = nil
                if var palette = commandPaletteState {
                    let result = palette.handleTextInput(textInput)
                    commandPaletteState = palette
                    if result.didConsumeEvent {
                        currentCursorIntent = .arrow
                        invalidations = LunaFrameInvalidationSet(.input)
                    } else {
                        invalidations = insertCommittedTextIntoEditor(textInput.text)
                    }
                } else if isFindPanelPresented {
                    let provider = MothLunaFindPanelSession(buffer: buffer)
                    let result = findPanelState.handleTextInput(
                        textInput,
                        provider: provider
                    )
                    if result.didConsumeEvent {
                        updateFindStatus()
                        currentCursorIntent = .text
                        invalidations = LunaFrameInvalidationSet(.input)
                    } else {
                        invalidations = insertCommittedTextIntoEditor(textInput.text)
                    }
                } else {
                    invalidations = insertCommittedTextIntoEditor(textInput.text)
                }
            }
        }

        runtimeAttributionRecorder.recordHostInvalidation(invalidations)
        return invalidations
    }

    public mutating func render(into framebuffer: inout LunaFramebuffer) {
        pendingFrameRenderReport = nil
        let renderStart = LunaMonotonicClock.nowNanoseconds()
        advanceTextSelectionAutoscroll()

        let size = LunaSizeI(
            width: framebuffer.width,
            height: framebuffer.height
        )
        let geometry = MothApplicationFrameGeometry(framebufferSize: size)
        let hasCompatibleCache = staticFrameCache?.matches(size: size) == true
        let damagePlan = MothApplicationFrameDamagePlan.make(
            invalidations: latestFrameInvalidations,
            geometry: geometry,
            hasCompatibleCache: hasCompatibleCache,
            hasActiveOverlay: menuBarState.isOpen
                || commandPaletteState != nil
                || isFindPanelPresented
        )

        if damagePlan.path == .partialDamage,
           let cache = staticFrameCache {
            let restoreStart = LunaMonotonicClock.nowNanoseconds()
            let restoredPixels = cache.restore(
                into: &framebuffer,
                regions: damagePlan.regions
            )
            let restoreEnd = LunaMonotonicClock.nowNanoseconds()

            if restoredPixels > 0 {
                let partialStart = LunaMonotonicClock.nowNanoseconds()
                drawPartialFrame(
                    into: &framebuffer,
                    geometry: geometry,
                    plan: damagePlan
                )
                let partialEnd = LunaMonotonicClock.nowNanoseconds()

                staticFrameCache?.update(
                    from: framebuffer,
                    regions: damagePlan.regions
                )

                let report = LunaFrameRenderReport(
                    path: .partialDamage,
                    invalidationClass: LunaFrameInvalidationClass(
                        invalidations: latestFrameInvalidations
                    ),
                    cacheRestoreNanoseconds: restoreEnd >= restoreStart
                        ? restoreEnd - restoreStart
                        : 0,
                    dynamicSceneNanoseconds: partialEnd >= partialStart
                        ? partialEnd - partialStart
                        : 0,
                    damagedRegionCount: damagePlan.regions.count,
                    damagedPixelCount: restoredPixels
                )
                latestFrameRenderReport = report
                pendingFrameRenderReport = report
                runtimeAttributionRecorder.recordFrame(path: report.path)
                return
            }
        }

        let palette = MothApplicationTheme.renderPalette
        framebuffer.clear(palette.windowBackground)
        framebuffer.fillRect(
            geometry.menuBarBounds,
            color: palette.chromeBackground
        )
        framebuffer.fillRect(
            geometry.documentBarBounds,
            color: palette.raisedBackground
        )
        framebuffer.fillRect(
            geometry.sidebarBounds,
            color: palette.chromeBackground
        )
        framebuffer.fillRect(
            geometry.minimapBounds,
            color: palette.minimapBackground
        )
        framebuffer.fillRect(
            geometry.statusBounds,
            color: palette.raisedBackground
        )
        framebuffer.fillRect(
            geometry.sidebarSeparatorBounds,
            color: palette.separator
        )
        framebuffer.fillRect(
            geometry.contentTopSeparatorBounds,
            color: palette.separator
        )
        framebuffer.fillRect(
            geometry.accentRuleBounds,
            color: activeAccent
        )

        drawChromeText(
            framebuffer: &framebuffer,
            statusHeight: geometry.statusBounds.h
        )
        drawSidebar(
            framebuffer: &framebuffer,
            sidebarWidth: geometry.sidebarBounds.w
        )
        let framePresentation = currentViewportPresentation()
        drawPaneEditors(
            framebuffer: &framebuffer,
            bounds: geometry.paneBounds,
            presentationBundle: framePresentation
        )
        drawMinimap(
            framebuffer: &framebuffer,
            left: geometry.minimapBounds.x,
            top: geometry.minimapBounds.y,
            width: geometry.minimapBounds.w,
            height: geometry.minimapBounds.h,
            accent: activeAccent,
            presentationBundle: framePresentation
        )
        // The restoration cache always represents the overlay-free base frame.
        // Menus and quick panels are transient and must never contaminate it.
        storeStaticFrameCache(from: framebuffer, size: size)
        drawFindPanel(into: &framebuffer)
        drawMenuSurface(into: &framebuffer)
        drawCommandPalette(into: &framebuffer)

        let renderEnd = LunaMonotonicClock.nowNanoseconds()
        let effectiveCacheMissReason = damagePlan.cacheMissReason
            ?? (damagePlan.path == .partialDamage
                ? .cacheRestoreFailed
                : .notApplicable)
        let report = LunaFrameRenderReport(
            path: .fullScene,
            invalidationClass: LunaFrameInvalidationClass(
                invalidations: latestFrameInvalidations
            ),
            cacheMissReason: effectiveCacheMissReason,
            staticSceneNanoseconds: renderEnd >= renderStart
                ? renderEnd - renderStart
                : 0
        )
        latestFrameRenderReport = report
        pendingFrameRenderReport = report
        runtimeAttributionRecorder.recordFrame(path: report.path)
    }


    private mutating func drawPartialFrame(
        into framebuffer: inout LunaFramebuffer,
        geometry: MothApplicationFrameGeometry,
        plan: MothApplicationFrameDamagePlan
    ) {
        let palette = MothApplicationTheme.renderPalette
        let framePresentation = currentViewportPresentation()

        switch plan.kind {
        case .documentEdit:
            framebuffer.fillRect(
                geometry.documentBarBounds,
                color: palette.raisedBackground
            )
            framebuffer.fillRect(
                geometry.paneBounds,
                color: palette.windowBackground
            )
            framebuffer.fillRect(
                geometry.minimapBounds,
                color: palette.minimapBackground
            )
            framebuffer.fillRect(
                geometry.statusBounds,
                color: palette.raisedBackground
            )
            framebuffer.fillRect(
                geometry.contentTopSeparatorBounds,
                color: palette.separator
            )
            framebuffer.fillRect(
                geometry.accentRuleBounds,
                color: activeAccent
            )

            drawDocumentTitle(framebuffer: &framebuffer)
            drawStatusText(
                framebuffer: &framebuffer,
                statusHeight: geometry.statusBounds.h
            )
            drawPaneEditors(
                framebuffer: &framebuffer,
                bounds: geometry.paneBounds,
                presentationBundle: framePresentation
            )
            drawMinimap(
                framebuffer: &framebuffer,
                left: geometry.minimapBounds.x,
                top: geometry.minimapBounds.y,
                width: geometry.minimapBounds.w,
                height: geometry.minimapBounds.h,
                accent: activeAccent,
                presentationBundle: framePresentation
            )

        case .paneVisual:
            framebuffer.fillRect(
                geometry.paneBounds,
                color: palette.windowBackground
            )
            framebuffer.fillRect(
                geometry.minimapBounds,
                color: palette.minimapBackground
            )
            framebuffer.fillRect(
                geometry.statusBounds,
                color: palette.raisedBackground
            )

            drawMinimap(
                framebuffer: &framebuffer,
                left: geometry.minimapBounds.x,
                top: geometry.minimapBounds.y,
                width: geometry.minimapBounds.w,
                height: geometry.minimapBounds.h,
                accent: activeAccent,
                presentationBundle: framePresentation
            )
            drawStatusText(
                framebuffer: &framebuffer,
                statusHeight: geometry.statusBounds.h
            )
            drawPaneEditors(
                framebuffer: &framebuffer,
                bounds: geometry.paneBounds,
                presentationBundle: framePresentation
            )

        case .fullScene:
            break
        }
    }

    private mutating func storeStaticFrameCache(
        from framebuffer: LunaFramebuffer,
        size: LunaSizeI
    ) {
        if staticFrameCache?.matches(size: size) != true {
            staticFrameCache = MothApplicationStaticFrameCache(size: size)
        }
        staticFrameCache?.replace(with: framebuffer)
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

    private func makePaneInteractionSnapshot() -> MothPaneInteractionSnapshot {
        let start = LunaMonotonicClock.nowNanoseconds()
        let bufferSnapshot = buffer.snapshot()
        let key = MothPaneInteractionSnapshotKey(
            documentID: document.snapshot().id.description,
            documentRevision: bufferSnapshot.revision.rawValue,
            framebufferWidth: framebufferSize.width,
            framebufferHeight: framebufferSize.height,
            paneGeometryGeneration: paneGeometryGeneration,
            paneViewGeneration: paneViewGeneration,
            activePaneID: paneWorkspace.activePaneID.rawValue
        )

        if let cached = paneInteractionSnapshotStore.cached(for: key) {
            let end = LunaMonotonicClock.nowNanoseconds()
            runtimeAttributionRecorder.recordInteractionSnapshotRequest(
                cacheHit: true,
                elapsedNanoseconds: end >= start ? end - start : 0
            )
            return cached
        }

        let built = MothPaneInteractionSnapshot(
            key: key,
            layout: paneLayout(),
            presentationBundle: currentViewportPresentation()
        )
        paneInteractionSnapshotStore.replace(with: built)
        let end = LunaMonotonicClock.nowNanoseconds()
        runtimeAttributionRecorder.recordInteractionSnapshotRequest(
            cacheHit: false,
            elapsedNanoseconds: end >= start ? end - start : 0
        )
        return built
    }


    private func interactionSurface(
        in snapshot: MothPaneInteractionSnapshot,
        at point: LunaPointI
    ) -> (paneID: LunaPaneID, surface: MothPaneEditorSurface)? {
        guard let frame = snapshot.contentFrame(at: point) else { return nil }
        return interactionSurface(in: snapshot, frame: frame)
    }

    private func interactionSurface(
        in snapshot: MothPaneInteractionSnapshot,
        forTextSurfaceID surfaceID: LunaNodeID?
    ) -> (paneID: LunaPaneID, surface: MothPaneEditorSurface)? {
        guard let frame = snapshot.contentFrame(forTextSurfaceID: surfaceID) else {
            return nil
        }
        return interactionSurface(in: snapshot, frame: frame)
    }

    private func interactionSurface(
        in snapshot: MothPaneInteractionSnapshot,
        frame: LunaPaneContentFrame
    ) -> (paneID: LunaPaneID, surface: MothPaneEditorSurface) {
        let resolved = snapshot.surface(for: frame) {
            makePaneSurface(
                paneID: frame.paneID,
                contentFrame: frame,
                presentationBundle: snapshot.presentationBundle
            )
        }
        if resolved.didBuild {
            runtimeAttributionRecorder.recordInteractionTargetSurfaceBuild()
        }
        return (frame.paneID, resolved.surface)
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
        contentFrame: LunaPaneContentFrame,
        presentationBundle suppliedBundle: MothDocumentViewportPresentation? = nil
    ) -> MothPaneEditorSurface {
        runtimeAttributionRecorder.recordPaneSurfaceBuild()
        let bundle = suppliedBundle ?? currentViewportPresentation()
        return MothPaneEditorSurface(
            paneID: paneID,
            contentFrame: contentFrame,
            viewState: viewState(for: paneID),
            snapshot: bundle.storageSnapshot,
            presentation: bundle.presentation,
            virtualizationContext: bundle.virtualizationContext,
            isActive: paneID == paneWorkspace.activePaneID,
            highlights: findHighlights(for: viewState(for: paneID))
        )
    }

    private func resolvedCursorIntent(
        at point: LunaPointI,
        interactionSnapshot suppliedSnapshot: MothPaneInteractionSnapshot? = nil,
        interactionTarget suppliedTarget: (
            paneID: LunaPaneID,
            surface: MothPaneEditorSurface
        )? = nil
    ) -> LunaCursorIntent {
        if commandPaletteState != nil || menuBarState.isOpen { return .arrow }
        if isFindPanelPresented {
            return findPanel()?.fieldHit(at: point) == nil ? .arrow : .text
        }
        if scrollbarInteractionState.isDragging { return .arrow }

        let snapshot = suppliedSnapshot ?? makePaneInteractionSnapshot()
        let target = suppliedTarget ?? interactionSurface(in: snapshot, at: point)
        if let target,
           target.surface.textView.layout().scrollbarLaneBounds.contains(
               x: point.x,
               y: point.y
           ) {
            return .arrow
        }
        if textSelectionInteractionState.isSelecting { return .text }

        let container = paneContainer()
        if let dividerIntent = container.cursorIntent(at: point) {
            return dividerIntent
        }
        if snapshot.contentFrame(at: point) != nil {
            return .text
        }
        return .arrow
    }

    private mutating func handlePointer(
        _ event: LunaPointerEvent
    ) -> LunaFrameInvalidationSet {
        if handleCommandPalettePointer(event) {
            return LunaFrameInvalidationSet(.input)
        }
        if handleMenuPointer(event) {
            return LunaFrameInvalidationSet(.input)
        }
        if handleFindPanelPointer(event) {
            return LunaFrameInvalidationSet(.input)
        }
        if handleDocumentTabsPointer(event) {
            return LunaFrameInvalidationSet(.input)
        }
        if handleOpenFilesPointer(event) {
            return LunaFrameInvalidationSet(.input)
        }

        let snapshot = makePaneInteractionSnapshot()
        let pointTarget = interactionSurface(in: snapshot, at: event.location)
        if handleScrollbarPointer(
            event,
            interactionSnapshot: snapshot,
            pointTarget: pointTarget
        ) {
            return LunaFrameInvalidationSet(.scrollChanged)
        }

        let changesAccent = event.phase == .down
        if changesAccent { pointerAccentIsActive.toggle() }

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

        let ownsDividerGesture = wasDraggingDivider
            || paneInteraction.isDraggingDivider
            || paneResult.resizedSplitID != nil
        if ownsDividerGesture {
            if paneResult.resizedSplitID != nil {
                paneGeometryGeneration &+= 1
                paneInteractionSnapshotStore.removeAll()
            }
            currentCursorIntent = resolvedCursorIntent(
                at: event.location,
                interactionSnapshot: snapshot,
                interactionTarget: pointTarget
            )
            textSelectionInteractionState.cancel()
            resetWrappedScrollAnchors()
            statusMessage = paneInteraction.isDraggingDivider
                ? "Resizing editor panes"
                : "Editor pane resize complete"
            return LunaFrameInvalidationSet(.input)
        }

        currentCursorIntent = resolvedCursorIntent(
            at: event.location,
            interactionSnapshot: snapshot,
            interactionTarget: pointTarget
        )

        let target: (paneID: LunaPaneID, surface: MothPaneEditorSurface)?
        if event.phase == .down {
            target = pointTarget
        } else {
            target = interactionSurface(
                in: snapshot,
                forTextSurfaceID: textSelectionInteractionState.activeSurfaceID
            )
        }

        guard let target else {
            if event.phase == .down { textSelectionInteractionState.cancel() }
            return changesAccent
                ? LunaFrameInvalidationSet(.input)
                : LunaFrameInvalidationSet()
        }

        let textView = target.surface.textView
        let presentation = viewState(for: target.paneID)
        let currentCaret = textView.document.location(
            forAbsoluteUTF8Offset: presentation.caret.rawValue
        )
        let currentSelection = presentation.selection.map {
            LunaTextRange(
                anchor: textView.document.location(
                    forAbsoluteUTF8Offset: $0.anchor.rawValue
                ),
                focus: textView.document.location(
                    forAbsoluteUTF8Offset: $0.focus.rawValue
                )
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
        currentCursorIntent = resolvedCursorIntent(
            at: event.location,
            interactionSnapshot: snapshot,
            interactionTarget: pointTarget
        )

        guard selectionResult.didConsumeEvent else {
            return changesAccent
                ? LunaFrameInvalidationSet(.input)
                : LunaFrameInvalidationSet()
        }
        applyTextSelectionResult(
            selectionResult,
            paneID: target.paneID,
            textView: textView
        )
        let selectedBytes = viewState(
            for: target.paneID
        ).selection?.normalizedRange.length ?? 0
        let gesture: String
        switch selectionResult.granularity ?? selectionInteraction.granularity {
        case .character:
            gesture = selectionResult.didEndGesture
                ? "selection complete"
                : "drag selection"
        case .word:
            gesture = "word selection"
        case .line:
            gesture = "line selection"
        }
        statusMessage = "\(gesture) in \(target.paneID.rawValue): bytes=\(selectedBytes)"
        return changesAccent
            ? LunaFrameInvalidationSet(.input)
            : LunaFrameInvalidationSet(.selectionChanged)
    }

    private mutating func handleScroll(_ event: LunaScrollEvent) -> Bool {
        guard commandPaletteState == nil, !menuBarState.isOpen else {
            return false
        }
        let snapshot = makePaneInteractionSnapshot()
        guard let target = interactionSurface(in: snapshot, at: event.location) else {
            return false
        }

        let viewport = viewState(for: target.paneID).viewport
        let result = LunaStaticTextScrollInteraction.handleScrollEvent(
            event,
            in: target.surface.textView,
            fractionalRowRemainder: viewport.verticalScrollRemainder
        )
        guard result.didConsumeEvent else { return false }

        mutateView(for: target.paneID) { view in
            view.viewport.firstVisibleLine = result.requestedScrollTopLine
            view.viewport.firstVisibleVisualRow = result.requestedScrollTopVisualRow
            view.viewport.verticalScrollRemainder = result.fractionalRowRemainder
        }
        statusMessage =
            "Scrolled \(target.paneID.rawValue) to visual row "
            + "\(result.requestedScrollTopVisualRow ?? result.requestedScrollTopLine)"
        currentCursorIntent = .arrow
        return true
    }

    private mutating func handleScrollbarPointer(
        _ event: LunaPointerEvent,
        interactionSnapshot snapshot: MothPaneInteractionSnapshot,
        pointTarget: (paneID: LunaPaneID, surface: MothPaneEditorSurface)?
    ) -> Bool {
        let target: (paneID: LunaPaneID, surface: MothPaneEditorSurface)?
        if let activeSurfaceID = scrollbarInteractionState.activeSurfaceID {
            target = interactionSurface(
                in: snapshot,
                forTextSurfaceID: activeSurfaceID
            )
        } else {
            target = pointTarget
        }
        guard let target else { return false }

        var state = scrollbarInteractionState
        let result = LunaStaticTextScrollInteraction.handlePointerEvent(
            event,
            in: target.surface.textView,
            state: &state
        )
        scrollbarInteractionState = state
        guard result.didConsumeEvent else { return false }

        textSelectionInteractionState.cancel()
        if event.phase == .down {
            paneWorkspace.activePaneID = target.paneID
        }
        if let line = result.requestedScrollTopLine {
            mutateView(for: target.paneID) { view in
                view.viewport.firstVisibleLine = line
                view.viewport.firstVisibleVisualRow = result.requestedScrollTopVisualRow
                view.viewport.verticalScrollRemainder = 0
            }
        }
        currentCursorIntent = .arrow
        if result.didBeginDrag {
            statusMessage = "Dragging scrollbar in \(target.paneID.rawValue)"
        } else if result.didEndDrag {
            statusMessage = "Scrollbar drag complete in \(target.paneID.rawValue)"
        } else {
            statusMessage = "Scrollbar page in \(target.paneID.rawValue)"
        }
        return true
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
                view.viewport.verticalScrollRemainder = 0
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
        guard textSelectionInteractionState.wantsContinuousUpdates else { return }
        let snapshot = makePaneInteractionSnapshot()
        guard let target = interactionSurface(
            in: snapshot,
            forTextSurfaceID: textSelectionInteractionState.activeSurfaceID
        ) else { return }

        var interaction = textSelectionInteractionState
        let result = LunaTextSelectionInteraction.advanceAutoscroll(
            in: target.surface.textView,
            state: &interaction
        )
        textSelectionInteractionState = interaction
        guard result.requestedVisualRowDelta != 0 || result.didChangeSelection else {
            return
        }
        applyTextSelectionResult(
            result,
            paneID: target.paneID,
            textView: target.surface.textView
        )
        statusMessage = "Edge autoscroll in \(target.paneID.rawValue)"
    }

    private mutating func resetWrappedScrollAnchors() {
        primaryView.viewport.firstVisibleVisualRow = nil
        primaryView.viewport.verticalScrollRemainder = 0
        secondaryView.viewport.firstVisibleVisualRow = nil
        secondaryView.viewport.verticalScrollRemainder = 0
        paneViewGeneration &+= 1
    }


    // MARK: - M3A document sheets and real tabs

    private func lunaTabID(for sheetID: MothDocumentSheetID) -> LunaShellTabID {
        LunaShellTabID(rawValue: sheetID.rawValue)
    }

    private func sheetID(for tabID: LunaShellTabID) -> MothDocumentSheetID {
        MothDocumentSheetID(rawValue: tabID.rawValue)
    }

    private func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func documentShellTabs() -> [LunaShellTab] {
        documentSheets.sheets.map { sheet in
            let liveDocument = sheet.id == documentSheets.activeSheetID
                ? document
                : sheet.document
            let snapshot = liveDocument.snapshot()
            return LunaShellTab(
                id: lunaTabID(for: sheet.id),
                title: snapshot.displayName,
                detail: snapshot.fileURL?.path,
                isDirty: snapshot.isDirty,
                isPinned: false,
                isClosable: true,
                accessibilityLabel: snapshot.fileURL?.path ?? snapshot.displayName
            )
        }
    }

    private func documentTabShell() -> LunaEditorShell {
        let tabs = documentShellTabs()
        var state = documentShellState
        state.tabStrip.activeTabID = documentSheets.activeSheetID.map {
            lunaTabID(for: $0)
        }
        state.normalize(tabs: tabs, sidebarItems: [], metrics: documentTabMetrics)
        return LunaEditorShell(
            id: LunaNodeID(rawValue: "moth.document-tabs"),
            bounds: MothApplicationFrameGeometry(
                framebufferSize: framebufferSize
            ).documentBarBounds,
            tabs: tabs,
            sidebarItems: [],
            statusSegments: [],
            state: state,
            theme: MothApplicationTheme.theme,
            metrics: documentTabMetrics
        )
    }

    private var documentTabMetrics: LunaEditorShellMetrics {
        LunaEditorShellMetrics(
            tabStripHeight: 38,
            statusBarHeight: 1,
            sidebarMinWidth: 0,
            sidebarDefaultWidth: 0,
            sidebarMaxWidth: 0,
            sidebarHeaderHeight: 0,
            sidebarRowHeight: 1,
            sidebarIndentWidth: 0,
            shellBorderWidth: 0,
            tabMinWidth: 112,
            tabMaxWidth: 224,
            pinnedTabWidth: 44,
            tabOverflowButtonWidth: 32,
            tabHorizontalPadding: 10,
            tabCloseSize: 12,
            tabDirtySize: 5,
            statusHorizontalPadding: 0,
            statusSegmentGap: 0,
            textScale: 1,
            glyphMetrics: MothUnicodeTextPainter.editorMetrics.glyphMetrics
        )
    }

    private func openFilesSidebarItems() -> [LunaSidebarItem] {
        documentSheets.sheets.map { sheet in
            let liveDocument = sheet.id == documentSheets.activeSheetID
                ? document
                : sheet.document
            let snapshot = liveDocument.snapshot()
            return LunaSidebarItem(
                id: LunaSidebarItemID(rawValue: sheet.id.rawValue),
                title: snapshot.displayName,
                subtitle: snapshot.fileURL?.path,
                kind: .file,
                isEnabled: true,
                isSelectable: true,
                accessibilityLabel: snapshot.fileURL?.path ?? snapshot.displayName
            )
        }
    }

    private var openFilesMetrics: LunaEditorShellMetrics {
        LunaEditorShellMetrics(
            tabStripHeight: 1,
            statusBarHeight: 1,
            sidebarMinWidth: 120,
            sidebarDefaultWidth: 236,
            sidebarMaxWidth: 360,
            sidebarHeaderHeight: 28,
            sidebarRowHeight: 24,
            sidebarIndentWidth: 0,
            shellBorderWidth: 0,
            tabMinWidth: 1,
            tabMaxWidth: 1,
            pinnedTabWidth: 1,
            tabOverflowButtonWidth: 1,
            tabHorizontalPadding: 0,
            tabCloseSize: 0,
            tabDirtySize: 5,
            statusHorizontalPadding: 0,
            statusSegmentGap: 0,
            textScale: 1,
            glyphMetrics: MothUnicodeTextPainter.editorMetrics.glyphMetrics
        )
    }

    private func openFilesShell() -> LunaEditorShell {
        let items = openFilesSidebarItems()
        var state = openFilesShellState
        state.sidebar.selectedItemID = documentSheets.activeSheetID.map {
            LunaSidebarItemID(rawValue: $0.rawValue)
        }
        state.normalize(tabs: [], sidebarItems: items, metrics: openFilesMetrics)
        return LunaEditorShell(
            id: LunaNodeID(rawValue: "moth.open-files"),
            bounds: MothApplicationFrameGeometry(
                framebufferSize: framebufferSize
            ).sidebarBounds,
            tabs: [],
            sidebarTitle: "OPEN FILES",
            sidebarItems: items,
            statusSegments: [],
            state: state,
            theme: MothApplicationTheme.theme,
            metrics: openFilesMetrics
        )
    }

    func documentTabLayout() -> LunaEditorShellLayout {
        documentTabShell().layout()
    }

    func openFilesLayout() -> LunaEditorShellLayout {
        openFilesShell().layout()
    }

    private mutating func synchronizeDocumentTabState() {
        let tabs = documentShellTabs()
        documentShellState.tabStrip.activeTabID = documentSheets.activeSheetID.map {
            lunaTabID(for: $0)
        }
        documentShellState.normalize(
            tabs: tabs,
            sidebarItems: [],
            metrics: documentTabMetrics
        )
        let openItems = openFilesSidebarItems()
        openFilesShellState.sidebar.selectedItemID = documentSheets.activeSheetID.map {
            LunaSidebarItemID(rawValue: $0.rawValue)
        }
        openFilesShellState.normalize(
            tabs: [],
            sidebarItems: openItems,
            metrics: openFilesMetrics
        )
    }

    private mutating func captureActiveDocumentSheet() {
        guard let id = documentSheets.activeSheetID else { return }
        _ = documentSheets.update(
            id: id,
            document: document,
            primaryView: primaryView,
            secondaryView: secondaryView,
            findPanelState: findPanelState
        )
    }

    @discardableResult
    private mutating func appendDocumentSheet(
        _ newDocument: MothFileDocument
    ) -> MothDocumentSheetID {
        captureActiveDocumentSheet()
        install(document: newDocument)
        findPanelState = LunaFindPanelState()
        let id = documentSheets.append(
            document: document,
            primaryView: primaryView,
            secondaryView: secondaryView,
            findPanelState: findPanelState
        )
        documentShellState.tabStrip.activeTabID = lunaTabID(for: id)
        synchronizeDocumentTabState()
        return id
    }

    @discardableResult
    public mutating func activateDocumentSheet(
        _ id: MothDocumentSheetID
    ) -> Bool {
        guard documentSheets.sheet(with: id) != nil else { return false }
        if documentSheets.activeSheetID == id { return true }
        captureActiveDocumentSheet()
        return loadDocumentSheet(id)
    }

    @discardableResult
    private mutating func loadDocumentSheet(
        _ id: MothDocumentSheetID
    ) -> Bool {
        guard let sheet = documentSheets.sheet(with: id) else { return false }
        document = sheet.document
        primaryView = sheet.primaryView
        secondaryView = sheet.secondaryView
        findPanelState = sheet.findPanelState
        findPanelPointerField = nil
        _ = documentSheets.activate(id)
        documentShellState.tabStrip.activeTabID = lunaTabID(for: id)
        paneViewGeneration &+= 1
        paneInteractionSnapshotStore.removeAll()
        staticFrameCache = nil
        textSelectionInteractionState.cancel()
        scrollbarInteractionState.cancel()
        paneInteractionState.cancelDrag()
        currentCursorIntent = .arrow
        synchronizeDocumentTabState()
        if isFindPanelPresented {
            refreshFindPanelResults(preservingSelectionNearCaret: true)
        }
        statusMessage = "Active tab: \(document.snapshot().displayName)"
        return true
    }

    @discardableResult
    public mutating func closeActiveDocumentSheet() -> Bool {
        guard let id = documentSheets.activeSheetID else { return false }
        return closeDocumentSheet(id)
    }

    @discardableResult
    public mutating func closeDocumentSheet(
        _ id: MothDocumentSheetID
    ) -> Bool {
        guard documentSheets.sheet(with: id) != nil else { return false }
        let originalID = documentSheets.activeSheetID
        if originalID != id {
            captureActiveDocumentSheet()
            guard loadDocumentSheet(id) else { return false }
        }

        document.history.breakCoalescing()
        guard prepareToReplaceOrCloseCurrentDocument(source: "moth.tab.close") else {
            if let originalID, originalID != id {
                _ = loadDocumentSheet(originalID)
            }
            return false
        }

        captureActiveDocumentSheet()
        let closingName = document.snapshot().displayName
        let closingDocumentID = document.snapshot().id.description
        guard let removal = documentSheets.remove(id) else { return false }
        viewportPresentationStore.invalidate(documentID: closingDocumentID)

        let preferredID: MothDocumentSheetID?
        if let originalID,
           originalID != id,
           documentSheets.sheet(with: originalID) != nil {
            preferredID = originalID
        } else {
            preferredID = removal.nextActiveID
        }

        if let preferredID {
            _ = loadDocumentSheet(preferredID)
        } else {
            install(
                document: MothFileDocument(
                    untitledText: "",
                    displayName: "untitled.txt"
                )
            )
            findPanelState = LunaFindPanelState()
            let replacementID = documentSheets.append(
                document: document,
                primaryView: primaryView,
                secondaryView: secondaryView,
                findPanelState: findPanelState
            )
            documentShellState.tabStrip.activeTabID = lunaTabID(
                for: replacementID
            )
            synchronizeDocumentTabState()
        }
        statusMessage = "Closed \(closingName)"
        return true
    }

    @discardableResult
    private mutating func selectAdjacentDocumentSheet(
        delta: Int
    ) -> Bool {
        let tabs = documentShellTabs()
        guard !tabs.isEmpty else { return false }
        var strip = documentShellState.tabStrip
        let selected = delta < 0
            ? strip.selectPreviousTab(in: tabs)
            : strip.selectNextTab(in: tabs)
        documentShellState.tabStrip = strip
        guard let selected else { return false }
        return activateDocumentSheet(sheetID(for: selected))
    }

    @discardableResult
    private mutating func selectDocumentSheet(at index: Int) -> Bool {
        guard documentSheets.sheets.indices.contains(index) else { return false }
        return activateDocumentSheet(documentSheets.sheets[index].id)
    }

    private mutating func handleDocumentTabsPointer(
        _ event: LunaPointerEvent
    ) -> Bool {
        let shell = documentTabShell()
        let layout = shell.layout()
        var state = documentShellState
        let result = shell.handlePointerEvent(event, state: &state)
        documentShellState = state
        guard result.didConsumeEvent else { return false }
        currentCursorIntent = .arrow

        if let selected = result.selectedTabID {
            _ = activateDocumentSheet(sheetID(for: selected))
        }
        if let closed = result.closedTabID {
            _ = closeDocumentSheet(sheetID(for: closed))
        }
        if result.didToggleTabOverflow {
            if let hidden = layout.hiddenTabIDs.first {
                _ = activateDocumentSheet(sheetID(for: hidden))
                statusMessage = "Selected hidden tab from overflow"
            }
            documentShellState.tabStrip.isOverflowPresented = false
        }
        return true
    }

    private mutating func handleOpenFilesPointer(
        _ event: LunaPointerEvent
    ) -> Bool {
        let shell = openFilesShell()
        var state = openFilesShellState
        let result = shell.handlePointerEvent(event, state: &state)
        openFilesShellState = state
        guard result.didConsumeEvent else { return false }
        currentCursorIntent = .arrow
        if let selected = result.selectedSidebarItemID {
            _ = activateDocumentSheet(
                MothDocumentSheetID(rawValue: selected.rawValue)
            )
        }
        return true
    }


    // MARK: - M2.2B2 clipboard and visible Find/Replace

    private func findPanel() -> LunaFindPanel? {
        guard isFindPanelPresented else { return nil }
        return LunaFindPanel(
            id: LunaNodeID(rawValue: "moth.find-panel"),
            bounds: LunaRectI(
                x: 0,
                y: 0,
                w: framebufferSize.width,
                h: max(1, framebufferSize.height - 24)
            ),
            state: findPanelState,
            theme: MothApplicationTheme.theme,
            metrics: LunaFindPanelMetrics(
                maxPanelWidth: 820,
                minPanelWidth: 520,
                bottomMargin: 18,
                sideMargin: 18,
                panelPadding: 10,
                fieldHeight: 28,
                rowGap: 6,
                buttonHeight: 24,
                optionWidth: 72,
                actionButtonWidth: 84,
                textScale: 1,
                titleScale: 1,
                glyphMetrics: MothUnicodeTextPainter.editorMetrics.glyphMetrics
            )
        )
    }

    func findPanelLayout() -> LunaFindPanelLayout? {
        findPanel()?.layout()
    }

    private mutating func handleFindPanelPointer(_ event: LunaPointerEvent) -> Bool {
        guard let panel = findPanel() else { return false }
        let layout = panel.layout()

        if let field = findPanelPointerField,
           event.phase == .moved || event.phase == .up {
            findPanelState.focusedField = field
            findPanelState.setCaretInFocusedField(
                utf8Offset: panel.utf8Offset(in: field, atX: event.location.x),
                extendingSelection: true
            )
            if event.phase == .up { findPanelPointerField = nil }
            currentCursorIntent = .text
            return true
        }

        guard event.phase == .down else {
            return layout.panelBounds.contains(x: event.location.x, y: event.location.y)
        }

        if !layout.panelBounds.contains(x: event.location.x, y: event.location.y) {
            let geometry = MothApplicationFrameGeometry(
                framebufferSize: framebufferSize
            )
            if geometry.documentBarBounds.contains(
                x: event.location.x,
                y: event.location.y
            ) || geometry.sidebarBounds.contains(
                x: event.location.x,
                y: event.location.y
            ) {
                return false
            }
            closeFindPanel()
            return false
        }

        if let fieldHit = panel.fieldHit(at: event.location) {
            findPanelState.focusedField = fieldHit.field
            findPanelState.setCaretInFocusedField(
                utf8Offset: fieldHit.utf8Offset,
                extendingSelection: event.modifiers.shift
            )
            findPanelPointerField = fieldHit.field
            currentCursorIntent = .text
            return true
        }

        let hit = panel.hitTest(event.location)
        switch hit {
        case panel.caseToggleNodeID:
            findPanelState.toggleCaseSensitive()
            refreshFindPanelResults()
        case panel.wholeWordToggleNodeID:
            findPanelState.toggleWholeWord()
            refreshFindPanelResults()
        case panel.regexToggleNodeID:
            findPanelState.toggleRegex()
            refreshFindPanelResults()
        case panel.previousButtonNodeID:
            _ = executeCommand(MothCommandID.findPrevious, source: "findPanel")
        case panel.nextButtonNodeID:
            _ = executeCommand(MothCommandID.findNext, source: "findPanel")
        case panel.replaceButtonNodeID:
            _ = executeCommand(MothCommandID.replaceCurrent, source: "findPanel")
        case panel.replaceAllButtonNodeID:
            _ = executeCommand(MothCommandID.replaceAll, source: "findPanel")
        default:
            break
        }
        currentCursorIntent = .arrow
        return true
    }

    private mutating func handleFindPanelKeyboard(_ event: LunaKeyboardEvent) -> Bool {
        guard isFindPanelPresented else { return false }
        let provider = MothLunaFindPanelSession(buffer: buffer)
        let result = findPanelState.handleKeyboardEvent(event, provider: provider)
        guard result.didConsumeEvent else { return false }

        if result.didDismiss {
            closeFindPanel()
            return true
        }
        if let action = result.requestedAction {
            let command = action == .findPrevious
                ? MothCommandID.findPrevious
                : MothCommandID.findNext
            _ = executeCommand(command, source: "findPanel.keyboard")
        } else {
            updateFindStatus()
        }
        currentCursorIntent = .text
        return true
    }

    private mutating func openFindPanel() {
        if !isFindPanelPresented {
            findPanelReturnPaneID = paneWorkspace.activePaneID
        }
        isFindPanelPresented = true
        findPanelPointerField = nil
        menuBarState.close()
        commandPaletteState = nil
        findPanelState.focusedField = .query

        if let selection = activeEditorSelectionRange {
            let selected = buffer.snapshot().text(in: selection)
            if !selected.contains("\n"), selected.utf8.count <= 512 {
                findPanelState.queryFieldState.setText(
                    selected,
                    selectingAll: true
                )
            } else {
                findPanelState.queryFieldState.selectAll()
            }
        } else {
            findPanelState.queryFieldState.selectAll()
        }
        refreshFindPanelResults(preservingSelectionNearCaret: true)
        currentCursorIntent = .text
    }

    private mutating func closeFindPanel() {
        captureActiveDocumentSheet()
        isFindPanelPresented = false
        findPanelPointerField = nil
        currentCursorIntent = .arrow
        statusMessage = "Find / Replace closed — focus returned to \(findPanelReturnPaneID.rawValue)"
    }

    private mutating func refreshFindPanelResults(
        preservingSelectionNearCaret: Bool = false
    ) {
        let provider = MothLunaFindPanelSession(buffer: buffer)
        let location: LunaTextLocation?
        if preservingSelectionNearCaret {
            location = currentViewportPresentation().presentation.document.location(
                forAbsoluteUTF8Offset: activeViewState.caret.rawValue
            )
        } else {
            location = nil
        }
        findPanelState.refreshResults(
            using: provider,
            preservingSelectionNear: location
        )
        updateFindStatus()
    }

    private mutating func refreshFindPanelAfterDocumentMutation() {
        guard isFindPanelPresented else { return }
        refreshFindPanelResults(preservingSelectionNearCaret: true)
    }

    private mutating func updateFindStatus() {
        statusMessage = findPanelState.results.statusText
    }

    private mutating func selectCurrentFindMatchInEditor() -> Bool {
        guard let match = findPanelState.results.selectedMatch else {
            updateFindStatus()
            return false
        }
        mutateActiveView { view in
            view.setSelection(
                anchor: MothTextOffset(rawValue: match.utf8Offset),
                focus: MothTextOffset(
                    rawValue: match.utf8Offset + match.utf8Length
                )
            )
            view.preferredUTF8Column = nil
        }
        ensureActiveCaretVisible()
        updateFindStatus()
        return true
    }

    private mutating func navigateFind(previous: Bool) -> Bool {
        guard findPanelState.results.errorMessage == nil else {
            updateFindStatus()
            return false
        }
        guard !findPanelState.query.isEmpty else {
            statusMessage = "Enter text to find"
            return false
        }
        refreshFindPanelResults()
        guard !findPanelState.results.matches.isEmpty else {
            updateFindStatus()
            return false
        }
        if previous {
            findPanelState.selectPrevious()
        } else {
            findPanelState.selectNext()
        }
        return selectCurrentFindMatchInEditor()
    }

    private mutating func performFindReplacement(replaceAll: Bool) -> MothHistoryActionResult? {
        refreshFindPanelResults()
        guard findPanelState.results.errorMessage == nil,
              !findPanelState.results.matches.isEmpty
        else {
            updateFindStatus()
            return nil
        }

        var session = MothFindSession(buffer: buffer)
        _ = session.update(
            query: MothLunaFindPanelSession.mothQuery(from: findPanelState.query)
        )
        if let selected = findPanelState.results.selectedMatch {
            session.selectMatch(startingAtUTF8Offset: selected.utf8Offset)
        }

        let result: MothHistoryActionResult?
        if paneWorkspace.activePaneID == Self.secondaryPaneID {
            var others = [primaryView]
            if replaceAll {
                result = session.replaceAll(
                    with: findPanelState.replaceText,
                    history: document.history,
                    originView: &secondaryView,
                    otherViews: &others
                )
            } else {
                result = session.replaceCurrent(
                    with: findPanelState.replaceText,
                    history: document.history,
                    originView: &secondaryView,
                    otherViews: &others
                )
            }
            primaryView = others[0]
        } else {
            var others = [secondaryView]
            if replaceAll {
                result = session.replaceAll(
                    with: findPanelState.replaceText,
                    history: document.history,
                    originView: &primaryView,
                    otherViews: &others
                )
            } else {
                result = session.replaceCurrent(
                    with: findPanelState.replaceText,
                    history: document.history,
                    originView: &primaryView,
                    otherViews: &others
                )
            }
            secondaryView = others[0]
        }

        guard let result else { return nil }
        paneViewGeneration &+= 1
        refreshFindPanelResults(preservingSelectionNearCaret: true)
        if !replaceAll { _ = selectCurrentFindMatchInEditor() }
        return result
    }

    private var activeEditorSelectionRange: MothTextRange? {
        guard let selection = activeViewState.selection,
              !selection.isCollapsed
        else { return nil }
        return selection.normalizedRange
    }

    private var activeEditorSelectedText: String? {
        guard let range = activeEditorSelectionRange else { return nil }
        return buffer.snapshot().text(in: range)
    }

    private func focusedClipboardSelection() -> String? {
        if isFindPanelPresented {
            return findPanelState.selectedTextInFocusedField
        }
        return activeEditorSelectedText
    }

    private mutating func copyFocusedSelection() -> Bool {
        guard let selected = focusedClipboardSelection(), !selected.isEmpty else {
            statusMessage = "Nothing selected to Copy"
            return false
        }
        do {
            try clipboardService.writeText(selected)
            statusMessage = "Copied \(selected.utf8.count) UTF-8 bytes"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private mutating func cutFocusedSelection() -> Bool {
        guard let selected = focusedClipboardSelection(), !selected.isEmpty else {
            statusMessage = "Nothing selected to Cut"
            return false
        }
        do {
            // Clipboard write must succeed before any destructive mutation.
            try clipboardService.writeText(selected)
        } catch {
            statusMessage = error.localizedDescription
            return false
        }

        if isFindPanelPresented {
            _ = findPanelState.replaceSelectionInFocusedField(with: "")
            refreshFindPanelResults()
            statusMessage = "Cut from Find / Replace field"
            return true
        }

        document.history.breakCoalescing()
        guard let result = performActiveInsert("") else {
            statusMessage = "Cut did not change the document"
            return false
        }
        refreshFindPanelAfterDocumentMutation()
        ensureActiveCaretVisible()
        statusMessage = "Cut: \(result.displayName)"
        return true
    }

    private mutating func pasteIntoFocusedSurface() -> Bool {
        let text: String
        do {
            guard let clipboardText = try clipboardService.readText(),
                  !clipboardText.isEmpty
            else {
                statusMessage = "Clipboard contains no plain text"
                return false
            }
            text = clipboardText
        } catch {
            statusMessage = error.localizedDescription
            return false
        }

        if isFindPanelPresented {
            _ = findPanelState.replaceSelectionInFocusedField(with: text)
            refreshFindPanelResults()
            statusMessage = "Pasted into Find / Replace field"
            return true
        }

        document.history.breakCoalescing()
        guard let result = performActiveInsert(text) else {
            statusMessage = "Paste did not change the document"
            return false
        }
        refreshFindPanelAfterDocumentMutation()
        ensureActiveCaretVisible()
        statusMessage = "Paste: \(result.displayName)"
        return true
    }

    private mutating func insertCommittedTextIntoEditor(
        _ text: String
    ) -> LunaFrameInvalidationSet {
        if let result = performActiveInsert(text) {
            statusMessage = result.displayName
            refreshFindPanelAfterDocumentMutation()
        }
        ensureActiveCaretVisible()
        return LunaFrameInvalidationSet(.textInput)
    }

    private func findHighlights(
        for view: MothEditorViewState
    ) -> [LunaStaticTextHighlight] {
        guard isFindPanelPresented,
              findPanelState.results.errorMessage == nil,
              !findPanelState.results.matches.isEmpty
        else { return [] }

        // Keep overlay work viewport-bounded even when a query has thousands of
        // matches in a large document. Navigation first scrolls the selected
        // match into this bounded window.
        let lowerLine = max(0, view.viewport.firstVisibleLine - 4)
        let upperLine = lowerLine + 192
        let selectedIndex = findPanelState.results.selectedMatchIndex
        var highlights: [LunaStaticTextHighlight] = []
        highlights.reserveCapacity(128)
        for (index, match) in findPanelState.results.matches.enumerated() {
            let range = match.range.normalized
            guard range.focus.lineIndex >= lowerLine,
                  range.anchor.lineIndex <= upperLine
            else { continue }
            let color: LunaColor = index == selectedIndex
                ? .hex("#B8AAFF88")
                : .hex("#705AFF40")
            highlights.append(
                LunaStaticTextHighlight(range: match.range, color: color)
            )
            if highlights.count >= 512 { break }
        }
        return highlights
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
                    .separator(id: "file.separator.close"),
                    menuItem(for: MothCommandID.closeTab),
                ]
            ),
            LunaMenuDefinition(
                id: "edit",
                title: "Edit",
                items: [
                    menuItem(for: MothCommandID.undo),
                    menuItem(for: MothCommandID.redo),
                    .separator(id: "edit.separator.clipboard"),
                    menuItem(for: MothCommandID.cut),
                    menuItem(for: MothCommandID.copy),
                    menuItem(for: MothCommandID.paste),
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
                items: [
                    menuItem(for: MothCommandID.showFind),
                    menuItem(for: MothCommandID.findNext),
                    menuItem(for: MothCommandID.findPrevious),
                    .separator(id: "find.separator.replace"),
                    menuItem(for: MothCommandID.replaceCurrent),
                    menuItem(for: MothCommandID.replaceAll),
                ]
            ),
            LunaMenuDefinition(
                id: "view",
                title: "View",
                items: [
                    menuItem(for: MothCommandID.nextTab),
                    menuItem(for: MothCommandID.previousTab),
                    .separator(id: "view.separator.panes"),
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
                        title: "Goto commands arrive with M4",
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
        captureActiveDocumentSheet()
        isFindPanelPresented = false
        findPanelPointerField = nil
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

    private mutating func handleKeyboardWithMeasuredInvalidation(
        _ event: LunaKeyboardEvent
    ) -> LunaFrameInvalidationSet {
        let beforeDocumentID = document.snapshot().id.description
        let beforeRevision = buffer.snapshot().revision
        let beforePrimary = primaryView
        let beforeSecondary = secondaryView

        handleKeyboard(event)

        let afterDocumentID = document.snapshot().id.description
        let afterRevision = buffer.snapshot().revision
        if afterDocumentID != beforeDocumentID {
            return LunaFrameInvalidationSet(.input)
        }
        if afterRevision != beforeRevision {
            return LunaFrameInvalidationSet(.textInput)
        }
        if primaryView.caret != beforePrimary.caret
            || primaryView.selection != beforePrimary.selection
            || secondaryView.caret != beforeSecondary.caret
            || secondaryView.selection != beforeSecondary.selection {
            return LunaFrameInvalidationSet(.selectionChanged)
        }
        if primaryView.viewport != beforePrimary.viewport
            || secondaryView.viewport != beforeSecondary.viewport {
            return LunaFrameInvalidationSet(.scrollChanged)
        }
        return LunaFrameInvalidationSet(.input)
    }

    private mutating func handleKeyboard(_ event: LunaKeyboardEvent) {
        if handleCommandPaletteKeyboard(event) { return }
        if handleMenuKeyboard(event) { return }
        if isFindPanelPresented {
            if handleCommandShortcut(event) { return }
            if handleFindPanelKeyboard(event) { return }
        }
        if handleCommandShortcut(event) { return }
        let snapshot = buffer.snapshot()

        switch event.key {
        case .backspace:
            if let result = performActiveDeleteBackward() {
                statusMessage = result.displayName
                refreshFindPanelAfterDocumentMutation()
            }
            ensureActiveCaretVisible()

        case .delete:
            if let result = performActiveDeleteForward() {
                statusMessage = result.displayName
                refreshFindPanelAfterDocumentMutation()
            }
            ensureActiveCaretVisible()

        case .enter:
            if let result = performActiveInsert("\n") {
                statusMessage = result.displayName
                refreshFindPanelAfterDocumentMutation()
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

        if let index = MothCommandID.tabIndex(for: command) {
            return index < documentSheetCount
                ? .enabled
                : .disabled("Tab \(index + 1) is not open")
        }

        if commandPaletteState != nil,
           [MothCommandID.cut, MothCommandID.copy, MothCommandID.paste]
            .contains(command) {
            return .disabled("Close the Command Palette before using the clipboard")
        }

        switch command {
        case MothCommandID.newFile, MothCommandID.openFile,
             MothCommandID.saveAs, MothCommandID.closeTab,
             MothCommandID.nextPane, MothCommandID.previousPane,
             MothCommandID.showCommandPalette, MothCommandID.showFind:
            return .enabled
        case MothCommandID.nextTab, MothCommandID.previousTab:
            return documentSheetCount > 1
                ? .enabled
                : .disabled("Only one document tab is open")
        case MothCommandID.save:
            return snapshot.isUntitled || snapshot.isDirty
                ? .enabled
                : .disabled("Document is already saved")
        case MothCommandID.undo:
            return history.canUndo ? .enabled : .disabled("Nothing to Undo")
        case MothCommandID.redo:
            return history.canRedo ? .enabled : .disabled("Nothing to Redo")
        case MothCommandID.copy, MothCommandID.cut:
            return focusedClipboardSelection()?.isEmpty == false
                ? .enabled
                : .disabled("Nothing is selected")
        case MothCommandID.paste:
            return clipboardService.isAvailable
                ? .enabled
                : .disabled("The system clipboard is unavailable")
        case MothCommandID.selectAll:
            if isFindPanelPresented {
                return findPanelState.focusedFieldIsEmpty
                    ? .disabled("The focused Find / Replace field is empty")
                    : .enabled
            }
            return snapshot.buffer.utf8Count > 0
                ? .enabled
                : .disabled("Document is empty")
        case MothCommandID.findNext, MothCommandID.findPrevious:
            if findPanelState.results.errorMessage != nil {
                return .disabled(findPanelState.results.statusText)
            }
            return findPanelState.query.isEmpty
                ? .disabled("Enter text to find")
                : .enabled
        case MothCommandID.replaceCurrent:
            guard isFindPanelPresented else {
                return .disabled("Open Find / Replace first")
            }
            return findPanelState.results.selectedMatch == nil
                ? .disabled(findPanelState.results.statusText)
                : .enabled
        case MothCommandID.replaceAll:
            guard isFindPanelPresented else {
                return .disabled("Open Find / Replace first")
            }
            return findPanelState.results.matches.isEmpty
                ? .disabled(findPanelState.results.statusText)
                : .enabled
        default:
            return .disabled("Unknown Moth command")
        }
    }

    mutating func performRegisteredCommand(
        _ command: LunaCommandID,
        context: LunaCommandContext
    ) -> LunaCommandExecutionResult {
        if ![
            MothCommandID.copy,
            MothCommandID.cut,
            MothCommandID.paste,
        ].contains(command) {
            document.history.breakCoalescing()
        }
        textSelectionInteractionState.cancel()
        paneInteractionState.cancelDrag()

        if let index = MothCommandID.tabIndex(for: command) {
            return selectDocumentSheet(at: index)
                ? .handled("Active tab: \(index + 1)")
                : .unhandled("Tab \(index + 1) is not open")
        }

        switch command {
        case MothCommandID.newFile:
            return createNewUntitledDocument()
                ? .handled("New document tab")
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
        case MothCommandID.closeTab:
            return closeActiveDocumentSheet()
                ? .handled(statusMessage)
                : .unhandled(statusMessage)
        case MothCommandID.undo:
            guard let result = undoDocument() else {
                return .unhandled(statusMessage)
            }
            return .handled("Undo: \(result.displayName)")
        case MothCommandID.redo:
            guard let result = redoDocument() else {
                return .unhandled(statusMessage)
            }
            return .handled("Redo: \(result.displayName)")
        case MothCommandID.copy:
            return copyFocusedSelection()
                ? .handled(statusMessage)
                : .unhandled(statusMessage)
        case MothCommandID.cut:
            return cutFocusedSelection()
                ? .handled(statusMessage)
                : .unhandled(statusMessage)
        case MothCommandID.paste:
            return pasteIntoFocusedSurface()
                ? .handled(statusMessage)
                : .unhandled(statusMessage)
        case MothCommandID.selectAll:
            if isFindPanelPresented {
                findPanelState.selectAllInFocusedField()
                return .handled("Selected Find / Replace field")
            }
            selectAllInActiveView()
            return .handled("Selected entire document")
        case MothCommandID.showFind:
            openFindPanel()
            return .handled("Find / Replace")
        case MothCommandID.findNext:
            return navigateFind(previous: false)
                ? .handled(statusMessage)
                : .unhandled(statusMessage)
        case MothCommandID.findPrevious:
            return navigateFind(previous: true)
                ? .handled(statusMessage)
                : .unhandled(statusMessage)
        case MothCommandID.replaceCurrent:
            guard let result = performFindReplacement(replaceAll: false) else {
                return .unhandled(statusMessage)
            }
            return .handled("Replace: \(result.displayName)")
        case MothCommandID.replaceAll:
            guard let result = performFindReplacement(replaceAll: true) else {
                return .unhandled(statusMessage)
            }
            return .handled("Replace All: \(result.displayName)")
        case MothCommandID.nextTab:
            return selectAdjacentDocumentSheet(delta: 1)
                ? .handled(statusMessage)
                : .unhandled("No next document tab")
        case MothCommandID.previousTab:
            return selectAdjacentDocumentSheet(delta: -1)
                ? .handled(statusMessage)
                : .unhandled("No previous document tab")
        case MothCommandID.nextPane:
            _ = paneWorkspace.traverse(.next, layout: paneLayout())
            return .handled("Active pane: \(paneWorkspace.activePaneID.rawValue)")
        case MothCommandID.previousPane:
            _ = paneWorkspace.traverse(.previous, layout: paneLayout())
            return .handled("Active pane: \(paneWorkspace.activePaneID.rawValue)")
        case MothCommandID.showCommandPalette:
            openCommandPalette()
            return .handled("Command Palette")
        default:
            return .unhandled("Unknown Moth command: \(command.rawValue)")
        }
    }

    private func commandContext(source: String) -> LunaCommandContext {
        let focusedSurface: String
        if commandPaletteState != nil {
            focusedSurface = "commandPalette"
        } else if isFindPanelPresented {
            focusedSurface = findPanelState.focusedField == .query
                ? "find.query"
                : "find.replace"
        } else {
            focusedSurface = "editor"
        }
        return LunaCommandContext(
            focusedSurface: focusedSurface,
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
        _ = appendDocumentSheet(
            MothFileDocument(
                untitledText: "",
                displayName: "untitled.txt"
            )
        )
        menuBarState.close()
        commandPaletteState = nil
        currentCursorIntent = .arrow
        statusMessage = "New untitled document tab"
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
        let document = currentViewportPresentation().presentation.document
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
        let document = currentViewportPresentation().presentation.document
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
            view.viewport.verticalScrollRemainder = 0
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
            view.viewport.verticalScrollRemainder = 0
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
        paneViewGeneration &+= 1
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
        let previousDocumentID = self.document.snapshot().id.description
        viewportPresentationStore.invalidate(documentID: previousDocumentID)
        self.document = document
        staticFrameCache = nil
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

    private func currentViewportPresentation() -> MothDocumentViewportPresentation {
        let lookupStart = LunaMonotonicClock.nowNanoseconds()
        let bufferSnapshot = buffer.snapshot()
        let key = MothDocumentViewportPresentationKey(
            presentationKey: MothDocumentPresentationKey(
                documentID: document.snapshot().id.description,
                revision: bufferSnapshot.revision.rawValue
            ),
            geometryGeneration: 0
        )
        if let cached = viewportPresentationStore.cachedPresentation(for: key) {
            let lookupEnd = LunaMonotonicClock.nowNanoseconds()
            runtimeAttributionRecorder.recordPresentationRequest(
                cacheHit: true,
                elapsedNanoseconds: lookupEnd >= lookupStart
                    ? lookupEnd - lookupStart
                    : 0
            )
            return cached
        }

        let built = viewportPresentationStore.presentation(for: key) {
            MothLunaTextStorageAdapter(buffer: buffer).textSnapshot()
        }
        let lookupEnd = LunaMonotonicClock.nowNanoseconds()
        runtimeAttributionRecorder.recordPresentationRequest(
            cacheHit: false,
            elapsedNanoseconds: lookupEnd >= lookupStart
                ? lookupEnd - lookupStart
                : 0
        )
        return built
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
        drawApplicationTitle(framebuffer: &framebuffer)
        drawDocumentTitle(framebuffer: &framebuffer)
        drawStatusText(
            framebuffer: &framebuffer,
            statusHeight: statusHeight
        )
    }

    private func drawApplicationTitle(
        framebuffer: inout LunaFramebuffer
    ) {
        let palette = MothApplicationTheme.renderPalette
        MothUnicodeTextPainter.draw(
            "MOTH TEXT",
            atX: 12,
            y: 9,
            color: palette.text,
            into: &framebuffer
        )
    }

    private func drawDocumentTitle(
        framebuffer: inout LunaFramebuffer
    ) {
        let palette = MothApplicationTheme.renderPalette
        let layout = documentTabLayout()
        let activeID = documentSheets.activeSheetID.map { lunaTabID(for: $0) }
        let hoveredID = documentShellState.tabStrip.hoveredTabID

        for frame in layout.tabFrames {
            let isActive = frame.tab.id == activeID
            let isHovered = frame.tab.id == hoveredID
            let fill = isActive
                ? palette.chromeBackground
                : (isHovered ? palette.windowBackground : palette.raisedBackground)
            framebuffer.fillRect(frame.bounds, color: fill)
            framebuffer.fillRect(
                LunaRectI(
                    x: frame.bounds.x + frame.bounds.w - 1,
                    y: frame.bounds.y + 5,
                    w: 1,
                    h: max(1, frame.bounds.h - 10)
                ),
                color: palette.separator
            )
            if isActive {
                framebuffer.fillRect(
                    LunaRectI(
                        x: frame.bounds.x,
                        y: frame.bounds.y + max(0, frame.bounds.h - 2),
                        w: frame.bounds.w,
                        h: 2
                    ),
                    color: activeAccent
                )
            }
            if let dirty = frame.dirtyIndicatorBounds {
                framebuffer.fillRect(dirty, color: activeAccent)
            }
            MothUnicodeTextPainter.draw(
                frame.tab.title,
                atX: frame.titleBounds.x,
                y: frame.titleBounds.y,
                color: palette.text,
                maximumWidth: frame.titleBounds.w,
                into: &framebuffer
            )
            if let close = frame.closeButtonBounds {
                let span = min(close.w, close.h)
                if span > 4 {
                    for offset in 2..<(span - 2) {
                        framebuffer.fillRect(
                            LunaRectI(
                                x: close.x + offset,
                                y: close.y + offset,
                                w: 1,
                                h: 1
                            ),
                            color: palette.text
                        )
                        framebuffer.fillRect(
                            LunaRectI(
                                x: close.x + span - offset - 1,
                                y: close.y + offset,
                                w: 1,
                                h: 1
                            ),
                            color: palette.text
                        )
                    }
                }
            }
        }

        if let overflow = layout.tabOverflowButtonBounds {
            framebuffer.fillRect(
                overflow,
                color: documentShellState.tabStrip.isOverflowPresented
                    ? palette.chromeBackground
                    : palette.raisedBackground
            )
            let y = overflow.y + overflow.h / 2
            let start = overflow.x + max(2, (overflow.w - 11) / 2)
            for offset in [0, 4, 8] {
                framebuffer.fillRect(
                    LunaRectI(x: start + offset, y: y, w: 3, h: 3),
                    color: palette.text
                )
            }
        }
    }

    private func drawStatusText(
        framebuffer: inout LunaFramebuffer,
        statusHeight: Int
    ) {
        let palette = MothApplicationTheme.renderPalette
        let documentSnapshot = document.snapshot()
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


    private func drawFindPanel(into framebuffer: inout LunaFramebuffer) {
        guard let panel = findPanel() else { return }
        var displayList = LunaDisplayList()
        panel.buildDisplayList(into: &displayList)
        LunaCPURenderer().render(displayList: displayList, into: &framebuffer)

        let theme = MothApplicationTheme.theme
        let text = panel.textLayout()
        MothUnicodeTextPainter.draw(
            text.title.text,
            atX: text.title.bounds.x,
            y: text.title.bounds.y + 3,
            color: theme.ui.panel.titleForeground.asRenderColor,
            maximumWidth: text.title.bounds.w,
            into: &framebuffer
        )
        let queryColor = panel.state.queryText.isEmpty
            ? theme.ui.textField.placeholderForeground.asRenderColor
            : theme.ui.textField.foreground.asRenderColor
        MothUnicodeTextPainter.draw(
            text.query.text,
            atX: text.query.bounds.x,
            y: text.query.bounds.y + 4,
            color: queryColor,
            maximumWidth: text.query.bounds.w,
            into: &framebuffer
        )
        if panel.state.isReplaceVisible {
            let replaceColor = panel.state.replaceText.isEmpty
                ? theme.ui.textField.placeholderForeground.asRenderColor
                : theme.ui.textField.foreground.asRenderColor
            MothUnicodeTextPainter.draw(
                text.replace.text,
                atX: text.replace.bounds.x,
                y: text.replace.bounds.y + 4,
                color: replaceColor,
                maximumWidth: text.replace.bounds.w,
                into: &framebuffer
            )
        }

        // Luna paints selection behind field text. Repaint the focused caret
        // after Moth's Unicode glyph pass so the insertion point cannot be
        // obscured by a glyph edge.
        let focusedField = panel.state.focusedField
        let focusedState = panel.state.fieldState(for: focusedField)
        let fieldBounds = focusedField == .query
            ? panel.layout().queryFieldBounds
            : panel.layout().replaceFieldBounds
        if !fieldBounds.isEmpty {
            let textBounds = LunaRectI(
                x: fieldBounds.x + 8,
                y: fieldBounds.y + 4,
                w: max(1, fieldBounds.w - 16),
                h: max(1, fieldBounds.h - 8)
            )
            let index = focusedState.characterIndex(
                forUTF8Offset: focusedState.caretUTF8Offset
            )
            let x = min(
                textBounds.x + max(0, textBounds.w - 1),
                textBounds.x + index * max(1, panel.metrics.glyphMetrics.advance)
            )
            framebuffer.fillRect(
                LunaRectI(x: x, y: textBounds.y, w: 1, h: textBounds.h),
                color: theme.ui.editor.caret.asRenderColor
            )
        }

        let statusColor = panel.state.results.errorMessage == nil
            ? theme.ui.panel.mutedForeground.asRenderColor
            : theme.ui.controlColors.accentStrong.asRenderColor
        MothUnicodeTextPainter.draw(
            text.status.text,
            atX: text.status.bounds.x,
            y: text.status.bounds.y + 2,
            color: statusColor,
            maximumWidth: text.status.bounds.w,
            into: &framebuffer
        )
        for button in text.buttons {
            MothUnicodeTextPainter.draw(
                button.label,
                atX: button.bounds.x + 8,
                y: button.bounds.y + 5,
                color: button.isSelected
                    ? theme.ui.menu.rowHoveredForeground.asRenderColor
                    : theme.ui.menu.rowForeground.asRenderColor,
                maximumWidth: max(0, button.bounds.w - 16),
                into: &framebuffer
            )
        }
    }

    private func drawSidebar(
        framebuffer: inout LunaFramebuffer,
        sidebarWidth: Int
    ) {
        let palette = MothApplicationTheme.renderPalette
        let layout = openFilesLayout()
        MothUnicodeTextPainter.draw(
            "OPEN FILES",
            atX: layout.sidebarHeaderBounds.x + 16,
            y: layout.sidebarHeaderBounds.y + 8,
            color: palette.mutedText,
            maximumWidth: max(0, layout.sidebarHeaderBounds.w - 24),
            into: &framebuffer
        )

        let activeID = documentSheets.activeSheetID
        for row in layout.sidebarRows {
            let id = MothDocumentSheetID(rawValue: row.item.id.rawValue)
            let isActive = id == activeID
            if isActive {
                framebuffer.fillRect(row.bounds, color: palette.raisedBackground)
                framebuffer.fillRect(
                    LunaRectI(x: row.bounds.x, y: row.bounds.y, w: 3, h: row.bounds.h),
                    color: activeAccent
                )
            }
            let sheet = documentSheets.sheet(with: id)
            let liveDocument = id == activeID ? document : sheet?.document
            let isDirty = liveDocument?.snapshot().isDirty == true
            if isDirty {
                framebuffer.fillRect(
                    LunaRectI(
                        x: row.titleBounds.x,
                        y: row.bounds.y + max(1, (row.bounds.h - 5) / 2),
                        w: 5,
                        h: 5
                    ),
                    color: activeAccent
                )
            }
            MothUnicodeTextPainter.draw(
                row.item.title,
                atX: row.titleBounds.x + (isDirty ? 10 : 0),
                y: row.titleBounds.y + 2,
                color: isActive ? activeAccent : palette.text,
                maximumWidth: max(0, row.titleBounds.w - (isDirty ? 10 : 0)),
                into: &framebuffer
            )
        }

        let hidden = max(0, documentSheetCount - layout.sidebarRows.count)
        if hidden > 0 {
            MothUnicodeTextPainter.draw(
                "+\(hidden) MORE OPEN",
                atX: 18,
                y: max(0, framebuffer.height - 46),
                color: palette.mutedText,
                maximumWidth: max(0, sidebarWidth - 28),
                into: &framebuffer
            )
        }
    }

    private func drawPaneEditors(
        framebuffer: inout LunaFramebuffer,
        bounds: LunaRectI,
        presentationBundle suppliedBundle: MothDocumentViewportPresentation? = nil
    ) {
        let palette = MothApplicationTheme.renderPalette
        let container = paneContainer(bounds: bounds)
        let layout = container.layout()
        let frames = layout.contentFrames(metrics: .editor)
        let presentationBundle = suppliedBundle
            ?? currentViewportPresentation()

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
            makePaneSurface(
                paneID: frame.paneID,
                contentFrame: frame,
                presentationBundle: presentationBundle
            ).draw(into: &framebuffer)
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
        accent: LunaRender.LunaRGBA8,
        presentationBundle suppliedBundle: MothDocumentViewportPresentation? = nil
    ) {
        let presentationBundle = suppliedBundle
            ?? currentViewportPresentation()
        let document = presentationBundle.presentation.document
        let usableWidth = max(8, width - 20)
        let plan = MothMinimapSamplePlan(
            logicalLineCount: document.lineCount,
            activeLogicalLineIndex: activeViewState.viewport.firstVisibleLine,
            availableHeight: max(0, height - 20),
            rowStride: 6
        )
        runtimeAttributionRecorder.recordMinimapPlan(
            sampleCount: plan.samples.count,
            metadataLookupCount: plan.samples.count
        )
        for sample in plan.samples {
            guard let line = document.lineMetadata(
                at: sample.logicalLineIndex
            ) else { continue }
            let y = top + 10 + sample.rowIndex * 6
            let boundedLength = min(usableWidth, line.utf8Length)
            let length = min(usableWidth, max(2, boundedLength * 2))
            framebuffer.fillRect(
                LunaRectI(x: left + 10, y: y, w: length, h: 2),
                color: sample.isActiveLineSample
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
