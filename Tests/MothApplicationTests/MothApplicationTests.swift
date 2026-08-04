// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaUI
import MothEditor
import MothTextCore
import MothWorkspace
@testable import MothApplication

final class MothApplicationTests: XCTestCase {
    func testShellSceneIsInvalidationDrivenAndTracksResize() {
        var scene = MothApplicationShellScene()
        XCTAssertFalse(scene.wantsContinuousRendering)

        let resized = LunaSizeI(width: 1440, height: 900)
        let invalidations = scene.handleHostEvent(
            .windowResized(resized),
            framebufferSize: resized
        )

        XCTAssertEqual(scene.framebufferSize, resized)
        XCTAssertTrue(invalidations.reasons.contains(.windowResized))
    }

    func testPointerPressChangesVisibleAccentState() {
        var scene = MothApplicationShellScene()
        let size = LunaSizeI(width: 1100, height: 720)
        let event = LunaPointerEvent(
            phase: .down,
            location: LunaPointI(x: 400, y: 120),
            button: .primary
        )

        let before = scene.pointerAccentIsActive
        let invalidations = scene.handleHostEvent(
            .pointer(event),
            framebufferSize: size
        )

        XCTAssertNotEqual(scene.pointerAccentIsActive, before)
        XCTAssertTrue(invalidations.reasons.contains(.input))
    }

    func testCommittedTextInputMutatesMothBufferAndPreservesSecondaryViewState() {
        var scene = MothApplicationShellScene(initialText: "abc")
        let secondaryID = scene.secondaryView.id
        let secondaryPreferred = scene.secondaryView.preferredUTF8Column
        let secondaryViewport = scene.secondaryView.viewport

        let invalidations = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "X")),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )

        XCTAssertEqual(scene.bufferSnapshot.text, "Xabc")
        XCTAssertEqual(scene.bufferSnapshot.revision, MothBufferRevision(rawValue: 1))
        XCTAssertEqual(scene.secondaryView.id, secondaryID)
        XCTAssertEqual(scene.secondaryView.preferredUTF8Column, secondaryPreferred)
        XCTAssertEqual(scene.secondaryView.viewport, secondaryViewport)
        XCTAssertTrue(invalidations.reasons.contains(.textInput))
    }

    func testLunaStorageAdapterProjectsImmutableMothSnapshot() {
        let buffer = MothInMemorySourceBuffer(text: "hello")
        let adapter = MothLunaTextStorageAdapter(buffer: buffer)
        let first = adapter.textSnapshot()
        _ = buffer.replace(MothTextRange(start: 5, end: 5), with: "!")
        let second = adapter.textSnapshot()

        XCTAssertEqual(first.text, "hello")
        XCTAssertEqual(first.revision, .initial)
        XCTAssertEqual(second.text, "hello!")
        XCTAssertEqual(second.revision, LunaDocumentContentRevision(rawValue: 1))
        XCTAssertEqual(first.documentID, second.documentID)
    }

    func testMothViewProjectsToIndependentLunaPresentationState() {
        let buffer = MothInMemorySourceBuffer(text: "one\ntwo")
        var first = MothEditorViewState(bufferID: buffer.id, caret: MothTextOffset(rawValue: 1), firstVisibleLine: 0)
        var second = MothEditorViewState(bufferID: buffer.id, caret: MothTextOffset(rawValue: 6), firstVisibleLine: 1)
        _ = first.synchronize(with: buffer.snapshot())
        _ = second.synchronize(with: buffer.snapshot())
        let snapshot = MothLunaTextStorageAdapter(buffer: buffer).textSnapshot()

        let firstProjection = MothLunaViewProjection.presentation(for: first, snapshot: snapshot)
        let secondProjection = MothLunaViewProjection.presentation(for: second, snapshot: snapshot)

        XCTAssertEqual(firstProjection.documentID, secondProjection.documentID)
        XCTAssertNotEqual(firstProjection.id, secondProjection.id)
        XCTAssertNotEqual(firstProjection.caret, secondProjection.caret)
        XCTAssertNotEqual(firstProjection.scrollState, secondProjection.scrollState)
    }

    func testMothFindSessionAdapterPerformsReplacementBehindLunaPanel() {
        let buffer = MothInMemorySourceBuffer(text: "cat dog cat")
        var adapter = MothLunaFindPanelSession(buffer: buffer)
        var panel = LunaFindPanelState(queryText: "cat", replaceText: "fox")
        panel.refreshResults(using: adapter)

        let result = panel.perform(.replaceAll, using: &adapter)

        XCTAssertTrue(result.didChangeDocument)
        XCTAssertEqual(result.replacementCount, 2)
        XCTAssertEqual(buffer.snapshot().text, "fox dog fox")
    }

    func testShellRendersDistinctChromeAndActualTextPixels() {
        var scene = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 800, height: 600),
            initialText: "MOTH"
        )
        var framebuffer = LunaFramebuffer(width: 800, height: 600)

        scene.render(into: &framebuffer)

        func pixel(atX x: Int, y: Int) -> [UInt8] {
            var result: [UInt8] = []
            framebuffer.withUnsafePixelBytes { pointer, stride in
                let start = pointer.advanced(by: y * stride + x * 4)
                result = Array(UnsafeBufferPointer(start: start, count: 4))
            }
            return result
        }

        XCTAssertNotEqual(pixel(atX: 10, y: 10), pixel(atX: 400, y: 300))
        XCTAssertNotEqual(pixel(atX: 10, y: 100), pixel(atX: 400, y: 300))

        // Sample the first primary-pane text row using the actual pane-bound
        // content geometry rather than a hard-coded pre-split coordinate.
        let content = try! XCTUnwrap(
            scene.paneContentFrame(for: MothApplicationShellScene.primaryPaneID)
        ).contentBounds
        var glyphPixels = Set<[UInt8]>()
        for y in (content.y + 4)..<min(content.y + 16, 600) {
            for x in (content.x + 52)..<min(content.x + 70, 800) {
                glyphPixels.insert(pixel(atX: x, y: y))
            }
        }
        XCTAssertGreaterThan(glyphPixels.count, 1)
    }
    func testScriptedOpenCommandInstallsFileBackedDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MothApplicationOpen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("opened.txt")
        try Data("opened from disk".utf8).write(to: file)

        let dialogs = LunaScriptedDialogService(openPathSelections: [[file.path]])
        var scene = MothApplicationShellScene(initialText: "old", dialogService: dialogs)
        _ = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(
                key: .other("o"),
                modifiers: LunaKeyboardModifiers(control: true)
            )),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )

        XCTAssertEqual(scene.documentSnapshot.fileURL, file.standardizedFileURL)
        XCTAssertEqual(scene.documentSnapshot.displayName, "opened.txt")
        XCTAssertEqual(scene.bufferSnapshot.text, "opened from disk")
        XCTAssertFalse(scene.documentSnapshot.isDirty)
    }

    func testScriptedSaveAsCommandWritesUntitledDocumentAndSuppressesShortcutText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MothApplicationSave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("saved.txt")

        let dialogs = LunaScriptedDialogService(
            savePathSelections: [destination.path],
            scriptedSelectionsAllowOverwrite: true
        )
        var scene = MothApplicationShellScene(initialText: "save me", dialogService: dialogs)
        _ = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(
                key: .other("s"),
                modifiers: LunaKeyboardModifiers(shift: true, control: true)
            )),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "s")),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )

        XCTAssertEqual(scene.documentSnapshot.fileURL, destination.standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "save me")
        XCTAssertEqual(scene.bufferSnapshot.text, "save me")
        XCTAssertFalse(scene.documentSnapshot.isDirty)
    }

    func testDirtyDocumentCanCancelApplicationTermination() {
        let dialogs = LunaScriptedDialogService(unsavedDecisions: [.cancel])
        var scene = MothApplicationShellScene(initialText: "base", dialogService: dialogs)
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "!")),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )

        XCTAssertTrue(scene.documentSnapshot.isDirty)
        XCTAssertFalse(scene.requestApplicationTermination())
        XCTAssertTrue(scene.documentSnapshot.isDirty)
    }

    func testDirtyUntitledDocumentCanSaveBeforeApplicationTermination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MothApplicationCloseSave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("close-saved.txt")
        let dialogs = LunaScriptedDialogService(
            unsavedDecisions: [.save],
            savePathSelections: [destination.path],
            scriptedSelectionsAllowOverwrite: true
        )
        var scene = MothApplicationShellScene(initialText: "base", dialogService: dialogs)
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "!")),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )

        XCTAssertTrue(scene.requestApplicationTermination())
        XCTAssertFalse(scene.documentSnapshot.isDirty)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "!base")
    }

    func testDirectSaveWritesSharedBufferAndClearsDirtyState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MothApplicationDirectSave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("direct.txt")
        try Data("base".utf8).write(to: destination)

        var scene = MothApplicationShellScene()
        try scene.openDocument(at: destination)
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "!")),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )
        XCTAssertTrue(scene.documentSnapshot.isDirty)

        _ = try scene.saveDocument()

        XCTAssertFalse(scene.documentSnapshot.isDirty)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "!base")
    }

    func testPaneBoundTextViewsWrapIndependentlyAtTheirOwnWidths() throws {
        let longLine = String(repeating: "pane bounded wrapping ", count: 30)
        let scene = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 1100, height: 720),
            initialText: longLine
        )

        let primary = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        ).layout()
        let secondary = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.secondaryPaneID)
        ).layout()

        XCTAssertGreaterThan(primary.totalVisualRowCount, 1)
        XCTAssertGreaterThan(secondary.totalVisualRowCount, primary.totalVisualRowCount)
        XCTAssertLessThan(
            secondary.textViewportBounds.w,
            primary.textViewportBounds.w
        )
    }

    func testSecondaryPaneActivationRoutesEditingToSecondaryView() throws {
        var scene = MothApplicationShellScene(initialText: "abc")
        let primaryCaret = scene.primaryView.caret
        let secondaryHeader = try XCTUnwrap(
            scene.paneContentFrame(for: MothApplicationShellScene.secondaryPaneID)
        ).headerBounds

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .down,
                location: LunaPointI(
                    x: secondaryHeader.x + max(1, secondaryHeader.w / 2),
                    y: secondaryHeader.y + max(1, secondaryHeader.h / 2)
                ),
                button: .primary
            )),
            framebufferSize: scene.framebufferSize
        )
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "Z")),
            framebufferSize: scene.framebufferSize
        )

        XCTAssertEqual(scene.activePaneID, MothApplicationShellScene.secondaryPaneID)
        XCTAssertEqual(scene.primaryView.caret, primaryCaret)
        XCTAssertEqual(scene.bufferSnapshot.text, "abcZ")
        XCTAssertEqual(scene.secondaryView.caret.rawValue, 4)
    }

    func testDividerResizeChangesPaneWidthsAndRewrapsText() throws {
        let longLine = String(repeating: "resize reflow ", count: 40)
        var scene = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 1100, height: 720),
            initialText: longLine
        )
        let beforeLayout = scene.paneLayout()
        let beforePrimary = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        ).layout()
        let divider = try XCTUnwrap(
            beforeLayout.dividerFrame(for: MothApplicationShellScene.mainSplitID)
        )
        let targetX = beforeLayout.bounds.x + Int(Double(beforeLayout.bounds.w) * 0.72)
        let y = divider.bounds.y + max(1, divider.bounds.h / 2)

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: divider.bounds.x, y: y),
                button: .primary
            )),
            framebufferSize: scene.framebufferSize
        )
        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .moved,
                location: LunaPointI(x: targetX, y: y),
                button: .primary
            )),
            framebufferSize: scene.framebufferSize
        )
        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .up,
                location: LunaPointI(x: targetX, y: y),
                button: .primary
            )),
            framebufferSize: scene.framebufferSize
        )

        let afterPrimary = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        ).layout()
        XCTAssertGreaterThan(afterPrimary.textViewportBounds.w, beforePrimary.textViewportBounds.w)
        XCTAssertLessThan(afterPrimary.totalVisualRowCount, beforePrimary.totalVisualRowCount)
    }

    func testControlTabMovesFocusWithoutMergingViewState() {
        var scene = MothApplicationShellScene(initialText: "one\ntwo\nthree")
        let primary = scene.primaryView
        let secondary = scene.secondaryView

        _ = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(
                key: .tab,
                modifiers: LunaKeyboardModifiers(control: true, option: true)
            )),
            framebufferSize: scene.framebufferSize
        )

        XCTAssertEqual(scene.activePaneID, MothApplicationShellScene.secondaryPaneID)
        XCTAssertEqual(scene.primaryView, primary)
        XCTAssertEqual(scene.secondaryView, secondary)
    }

    func testDividerHoverRequestsResizeCursorWithoutCapture() throws {
        var scene = MothApplicationShellScene()
        let divider = try XCTUnwrap(
            scene.paneLayout().dividerFrame(for: MothApplicationShellScene.mainSplitID)
        )

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .moved,
                location: LunaPointI(x: divider.bounds.x + divider.bounds.w / 2, y: divider.bounds.y + divider.bounds.h / 2)
            )),
            framebufferSize: scene.framebufferSize
        )

        XCTAssertEqual(scene.cursorIntent, .resizeHorizontal)
        XCTAssertFalse(scene.wantsPointerCapture)
    }

    func testDividerDragKeepsResizeCursorAndCaptureOutsideWindowUntilRelease() throws {
        var scene = MothApplicationShellScene()
        let divider = try XCTUnwrap(
            scene.paneLayout().dividerFrame(for: MothApplicationShellScene.mainSplitID)
        )

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: divider.bounds.x + divider.bounds.w / 2, y: divider.bounds.y + divider.bounds.h / 2),
                button: .primary
            )),
            framebufferSize: scene.framebufferSize
        )
        XCTAssertEqual(scene.cursorIntent, .resizeHorizontal)
        XCTAssertTrue(scene.wantsPointerCapture)

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .moved,
                location: LunaPointI(x: -100, y: -100),
                button: .primary
            )),
            framebufferSize: scene.framebufferSize
        )
        XCTAssertEqual(scene.cursorIntent, .resizeHorizontal)
        XCTAssertTrue(scene.wantsPointerCapture)

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .up,
                location: LunaPointI(x: -100, y: -100),
                button: .primary
            )),
            framebufferSize: scene.framebufferSize
        )
        XCTAssertFalse(scene.wantsPointerCapture)
        XCTAssertEqual(scene.cursorIntent, .arrow)
    }

    func testEditorContentRequestsTextCursor() throws {
        var scene = MothApplicationShellScene()
        let content = try XCTUnwrap(
            scene.paneContentFrame(for: MothApplicationShellScene.primaryPaneID)
        ).contentBounds

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .moved,
                location: LunaPointI(x: content.x + 20, y: content.y + 20)
            )),
            framebufferSize: scene.framebufferSize
        )

        XCTAssertEqual(scene.cursorIntent, .text)
        XCTAssertFalse(scene.wantsPointerCapture)
    }

    func testPointerCaptureLossCancelsActiveDividerDrag() throws {
        var scene = MothApplicationShellScene()
        let divider = try XCTUnwrap(
            scene.paneLayout().dividerFrame(for: MothApplicationShellScene.mainSplitID)
        )
        let center = LunaPointI(
            x: divider.bounds.x + divider.bounds.w / 2,
            y: divider.bounds.y + divider.bounds.h / 2
        )

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .down, location: center, button: .primary)),
            framebufferSize: scene.framebufferSize
        )
        XCTAssertTrue(scene.wantsPointerCapture)

        _ = scene.handleHostEvent(
            .pointerCaptureLost,
            framebufferSize: scene.framebufferSize
        )

        XCTAssertFalse(scene.wantsPointerCapture)
        XCTAssertEqual(scene.cursorIntent, .arrow)
    }

    func testClickDragSelectionIsIndependentPerPane() throws {
        var scene = MothApplicationShellScene(initialText: "alpha beta gamma")
        let secondaryBefore = scene.secondaryView
        let textView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let row = try XCTUnwrap(textView.layout().visibleLines.first)
        let start = LunaPointI(
            x: row.textBounds.x + row.rowGeometry.x(forUTF8Offset: 1),
            y: row.rowBounds.y + row.rowBounds.h / 2
        )
        let end = LunaPointI(
            x: row.textBounds.x + row.rowGeometry.x(forUTF8Offset: 9),
            y: row.rowBounds.y + row.rowBounds.h / 2
        )

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .down, location: start)),
            framebufferSize: scene.framebufferSize
        )
        XCTAssertTrue(scene.wantsPointerCapture)
        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .moved, location: end, clickCount: 0)),
            framebufferSize: scene.framebufferSize
        )
        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .up, location: end)),
            framebufferSize: scene.framebufferSize
        )

        XCTAssertGreaterThan(scene.primaryView.selection?.normalizedRange.length ?? 0, 0)
        XCTAssertEqual(scene.secondaryView, secondaryBefore)
        XCTAssertFalse(scene.wantsPointerCapture)
    }

    func testDoubleClickSelectsUnicodeWordAndTypingReplacesIt() throws {
        var scene = MothApplicationShellScene(initialText: "héllo world")
        let textView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let row = try XCTUnwrap(textView.layout().visibleLines.first)
        let click = LunaPointI(
            x: row.textBounds.x + row.rowGeometry.x(forUTF8Offset: 3),
            y: row.rowBounds.y + row.rowBounds.h / 2
        )

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .down, location: click, clickCount: 2)),
            framebufferSize: scene.framebufferSize
        )
        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .up, location: click, clickCount: 2)),
            framebufferSize: scene.framebufferSize
        )

        XCTAssertEqual(scene.primaryView.selection?.anchor.rawValue, 0)
        XCTAssertEqual(scene.primaryView.selection?.focus.rawValue, 6)

        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "X")),
            framebufferSize: scene.framebufferSize
        )
        XCTAssertEqual(scene.bufferSnapshot.text, "X world")
        XCTAssertNil(scene.primaryView.selection)
    }

    func testTripleClickSelectsWholeLogicalLineIncludingNewline() throws {
        var scene = MothApplicationShellScene(initialText: "one\ntwo")
        let textView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let row = try XCTUnwrap(textView.layout().visibleLines.first)
        let click = LunaPointI(
            x: row.textBounds.x + row.rowGeometry.x(forUTF8Offset: 1),
            y: row.rowBounds.y + row.rowBounds.h / 2
        )

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .down, location: click, clickCount: 3)),
            framebufferSize: scene.framebufferSize
        )
        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .up, location: click, clickCount: 3)),
            framebufferSize: scene.framebufferSize
        )

        XCTAssertEqual(scene.primaryView.selection?.normalizedRange.start.rawValue, 0)
        XCTAssertEqual(scene.primaryView.selection?.normalizedRange.end.rawValue, 4)
    }

    func testShiftClickExtendsFromExistingCaretAnchor() throws {
        var scene = MothApplicationShellScene(initialText: "alpha beta")
        let textView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let row = try XCTUnwrap(textView.layout().visibleLines.first)
        func point(_ utf8Offset: Int) -> LunaPointI {
            LunaPointI(
                x: row.textBounds.x + row.rowGeometry.x(forUTF8Offset: utf8Offset),
                y: row.rowBounds.y + row.rowBounds.h / 2
            )
        }

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .down, location: point(2))),
            framebufferSize: scene.framebufferSize
        )
        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .up, location: point(2))),
            framebufferSize: scene.framebufferSize
        )
        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(
                phase: .down,
                location: point(8),
                modifiers: LunaKeyboardModifiers(shift: true)
            )),
            framebufferSize: scene.framebufferSize
        )

        XCTAssertEqual(scene.primaryView.selection?.anchor.rawValue, 2)
        XCTAssertEqual(scene.primaryView.selection?.focus.rawValue, 8)
    }

    func testEdgeAutoscrollAdvancesActivePaneAndRetainsSelectionCapture() throws {
        var scene = MothApplicationShellScene(
            initialText: (0..<80).map { "line \($0) selection target" }.joined(separator: "\n")
        )
        let textView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let layout = textView.layout()
        let first = try XCTUnwrap(layout.visibleLines.first)
        let start = LunaPointI(
            x: first.textBounds.x + 1,
            y: first.rowBounds.y + first.rowBounds.h / 2
        )
        let outside = LunaPointI(
            x: layout.textViewportBounds.x + 20,
            y: layout.textViewportBounds.y + layout.textViewportBounds.h + 60
        )

        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .down, location: start)),
            framebufferSize: scene.framebufferSize
        )
        _ = scene.handleHostEvent(
            .pointer(LunaPointerEvent(phase: .moved, location: outside, clickCount: 0)),
            framebufferSize: scene.framebufferSize
        )

        XCTAssertTrue(scene.wantsPointerCapture)
        XCTAssertTrue(scene.wantsContinuousRendering)
        XCTAssertGreaterThan(scene.primaryView.viewport.firstVisibleVisualRow ?? 0, 0)
        XCTAssertGreaterThan(scene.primaryView.selection?.normalizedRange.length ?? 0, 0)

        _ = scene.handleHostEvent(
            .pointerCaptureLost,
            framebufferSize: scene.framebufferSize
        )
        XCTAssertFalse(scene.wantsPointerCapture)
        XCTAssertFalse(scene.wantsContinuousRendering)
    }

}
