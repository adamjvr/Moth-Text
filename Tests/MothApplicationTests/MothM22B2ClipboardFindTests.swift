// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCommands
import LunaCore
import LunaHostCore
import LunaInput
import LunaUI
@testable import MothApplication
import MothTextCore

final class MothM22B2ClipboardFindTests: XCTestCase {
    private let size = LunaSizeI(width: 1100, height: 720)

    func testCopyWritesUnicodeSelectionWithoutCreatingHistory() throws {
        let clipboard = LunaInMemoryClipboardService()
        var scene = MothApplicationShellScene(
            initialText: "café\nλ",
            clipboardService: clipboard
        )

        _ = scene.executeCommand(MothCommandID.selectAll)
        let result = scene.executeCommand(MothCommandID.copy)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(try clipboard.readText(), "café\nλ")
        XCTAssertEqual(scene.bufferSnapshot.text, "café\nλ")
        XCTAssertFalse(scene.historyStatus.canUndo)
    }

    func testCutWritesBeforeMutationAndOneUndoRestoresSelection() throws {
        let clipboard = LunaInMemoryClipboardService()
        var scene = MothApplicationShellScene(
            initialText: "cut me",
            clipboardService: clipboard
        )
        _ = scene.executeCommand(MothCommandID.selectAll)

        let result = scene.executeCommand(MothCommandID.cut)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(try clipboard.readText(), "cut me")
        XCTAssertEqual(scene.bufferSnapshot.text, "")
        XCTAssertEqual(scene.historyStatus.undoGroupCount, 1)

        _ = scene.executeCommand(MothCommandID.undo)
        XCTAssertEqual(scene.bufferSnapshot.text, "cut me")
    }

    func testFailedClipboardWriteLeavesCutSelectionAndHistoryUntouched() {
        let clipboard = LunaInMemoryClipboardService()
        clipboard.failNextWrite()
        var scene = MothApplicationShellScene(
            initialText: "preserve me",
            clipboardService: clipboard
        )
        _ = scene.executeCommand(MothCommandID.selectAll)

        let result = scene.executeCommand(MothCommandID.cut)

        XCTAssertFalse(result.didHandle)
        XCTAssertEqual(scene.bufferSnapshot.text, "preserve me")
        XCTAssertEqual(
            scene.primaryView.selection?.normalizedRange,
            MothTextRange(start: 0, end: 11)
        )
        XCTAssertFalse(scene.historyStatus.canUndo)
    }

    func testPasteReplacesSelectionAsOneUndoableUnicodeEdit() {
        let clipboard = LunaInMemoryClipboardService(text: "βeta\nline two")
        var scene = MothApplicationShellScene(
            initialText: "replace",
            clipboardService: clipboard
        )
        _ = scene.executeCommand(MothCommandID.selectAll)

        let result = scene.executeCommand(MothCommandID.paste)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(scene.bufferSnapshot.text, "βeta\nline two")
        XCTAssertEqual(scene.historyStatus.undoGroupCount, 1)
        _ = scene.executeCommand(MothCommandID.undo)
        XCTAssertEqual(scene.bufferSnapshot.text, "replace")
    }

    func testFindFieldClipboardCommandsNeverMutateDocument() throws {
        let clipboard = LunaInMemoryClipboardService(text: "needle")
        var scene = MothApplicationShellScene(
            initialText: "document remains",
            clipboardService: clipboard
        )
        _ = scene.executeCommand(MothCommandID.showFind)

        _ = scene.executeCommand(MothCommandID.paste)
        XCTAssertEqual(scene.findPanelSnapshot.queryText, "needle")
        XCTAssertEqual(scene.bufferSnapshot.text, "document remains")

        _ = scene.executeCommand(MothCommandID.selectAll)
        _ = scene.executeCommand(MothCommandID.copy)
        XCTAssertEqual(try clipboard.readText(), "needle")
        XCTAssertEqual(scene.bufferSnapshot.text, "document remains")
        XCTAssertFalse(scene.historyStatus.canUndo)
    }

    func testFindNavigationSelectsMatchInActiveEditorPane() {
        var scene = MothApplicationShellScene(
            initialText: "cat dog cat",
            clipboardService: LunaInMemoryClipboardService()
        )
        _ = scene.executeCommand(MothCommandID.showFind)
        type("cat", into: &scene)

        let result = scene.executeCommand(MothCommandID.findNext)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(
            scene.primaryView.selection?.normalizedRange,
            MothTextRange(start: 8, end: 11)
        )
        XCTAssertEqual(scene.findPanelSnapshot.results.statusText, "2 of 2")
    }

    func testReplaceAllIsOneUndoGroup() {
        var scene = MothApplicationShellScene(
            initialText: "cat dog cat",
            clipboardService: LunaInMemoryClipboardService()
        )
        _ = scene.executeCommand(MothCommandID.showFind)
        type("cat", into: &scene)
        sendKey(.tab, to: &scene)
        type("fox", into: &scene)

        let result = scene.executeCommand(MothCommandID.replaceAll)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(scene.bufferSnapshot.text, "fox dog fox")
        XCTAssertEqual(scene.historyStatus.undoGroupCount, 1)
        _ = scene.executeCommand(MothCommandID.undo)
        XCTAssertEqual(scene.bufferSnapshot.text, "cat dog cat")
    }

    func testFindStateIsIndependentPerDocumentSheet() throws {
        var scene = MothApplicationShellScene(
            initialText: "alpha document",
            clipboardService: LunaInMemoryClipboardService()
        )
        let firstSheet = try XCTUnwrap(scene.activeDocumentSheetID)
        _ = scene.executeCommand(MothCommandID.showFind)
        type("alpha", into: &scene)

        _ = scene.executeCommand(MothCommandID.newFile)
        let secondSheet = try XCTUnwrap(scene.activeDocumentSheetID)
        type("beta", into: &scene)
        XCTAssertEqual(scene.findPanelSnapshot.queryText, "beta")

        XCTAssertTrue(scene.activateDocumentSheet(firstSheet))
        XCTAssertEqual(scene.findPanelSnapshot.queryText, "alpha")
        XCTAssertTrue(scene.activateDocumentSheet(secondSheet))
        XCTAssertEqual(scene.findPanelSnapshot.queryText, "beta")
    }

    func testInvalidRegexReportsVisibleErrorAndCannotReplace() throws {
        var scene = MothApplicationShellScene(
            initialText: "unchanged text",
            clipboardService: LunaInMemoryClipboardService()
        )
        _ = scene.executeCommand(MothCommandID.showFind)
        type("[", into: &scene)

        let layout = try XCTUnwrap(scene.findPanelLayout())
        sendPointerDown(
            x: layout.regexToggleBounds.x + 2,
            y: layout.regexToggleBounds.y + 2,
            to: &scene
        )

        XCTAssertNotNil(scene.findPanelSnapshot.results.errorMessage)
        XCTAssertTrue(scene.findPanelSnapshot.results.statusText.contains("Invalid regular expression"))
        XCTAssertFalse(
            scene.commandAvailability(for: MothCommandID.replaceAll).isEnabled
        )
        let result = scene.executeCommand(MothCommandID.replaceAll)
        XCTAssertFalse(result.didHandle)
        XCTAssertEqual(scene.bufferSnapshot.text, "unchanged text")
        XCTAssertFalse(scene.historyStatus.canUndo)
    }

    func testEscapeClosesFindAndSubsequentTextReturnsToEditor() {
        var scene = MothApplicationShellScene(
            initialText: "abc",
            clipboardService: LunaInMemoryClipboardService()
        )
        _ = scene.executeCommand(MothCommandID.showFind)
        type("query", into: &scene)
        sendKey(.escape, to: &scene)
        XCTAssertFalse(scene.isFindPanelOpen)

        type("X", into: &scene)
        XCTAssertEqual(scene.bufferSnapshot.text, "Xabc")
    }

    private func type(_ text: String, into scene: inout MothApplicationShellScene) {
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: text)),
            framebufferSize: size
        )
    }

    private func sendKey(
        _ key: LunaKeyboardKey,
        modifiers: LunaKeyboardModifiers = LunaKeyboardModifiers(),
        to scene: inout MothApplicationShellScene
    ) {
        _ = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(key: key, modifiers: modifiers)),
            framebufferSize: size
        )
    }

    private func sendPointerDown(
        x: Int,
        y: Int,
        to scene: inout MothApplicationShellScene
    ) {
        _ = scene.handleHostEvent(
            .pointer(
                LunaPointerEvent(
                    phase: .down,
                    location: LunaPointI(x: x, y: y),
                    button: .primary
                )
            ),
            framebufferSize: size
        )
    }
}
