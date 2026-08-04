// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaCore
import LunaHostCore
import LunaInput
@testable import MothApplication
import MothEditor
import MothTextCore
import MothWorkspace

final class MothApplicationHistoryTests: XCTestCase {
    private let size = LunaSizeI(width: 1100, height: 720)

    func testTextInputUndoAndShiftRedoUseDocumentHistory() {
        var scene = MothApplicationShellScene(initialText: "")

        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "hello")),
            framebufferSize: size
        )
        XCTAssertEqual(scene.bufferSnapshot.text, "hello")
        XCTAssertTrue(scene.historyStatus.canUndo)
        XCTAssertTrue(scene.documentSnapshot.isDirty)

        sendShortcut("z", to: &scene)
        XCTAssertEqual(scene.bufferSnapshot.text, "")
        XCTAssertFalse(scene.documentSnapshot.isDirty)
        XCTAssertEqual(scene.statusMessage, "Undo: Insert Text")

        sendShortcut("z", shift: true, to: &scene)
        XCTAssertEqual(scene.bufferSnapshot.text, "hello")
        XCTAssertTrue(scene.documentSnapshot.isDirty)
        XCTAssertEqual(scene.statusMessage, "Redo: Insert Text")
    }

    func testCtrlYRedoAndShortcutTextSuppression() {
        var scene = MothApplicationShellScene(initialText: "")
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "x")),
            framebufferSize: size
        )
        sendShortcut("z", to: &scene)

        // SDL may emit a committed text-input event for the physical shortcut.
        // Moth must suppress it rather than insert the shortcut letter.
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "z")),
            framebufferSize: size
        )
        XCTAssertEqual(scene.bufferSnapshot.text, "")

        sendShortcut("y", to: &scene)
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "y")),
            framebufferSize: size
        )
        XCTAssertEqual(scene.bufferSnapshot.text, "x")
    }

    func testUndoFromSecondaryPaneKeepsSecondaryActiveAndRestoresOriginView() {
        var scene = MothApplicationShellScene(initialText: "abc")
        let primaryBefore = scene.primaryView
        let secondaryViewportBefore = scene.secondaryView.viewport

        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "X")),
            framebufferSize: size
        )
        XCTAssertEqual(scene.bufferSnapshot.text, "Xabc")

        _ = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(key: .tab, modifiers: LunaKeyboardModifiers(control: true, option: true))),
            framebufferSize: size
        )
        XCTAssertEqual(scene.activePaneID, MothApplicationShellScene.secondaryPaneID)

        sendShortcut("z", to: &scene)

        XCTAssertEqual(scene.activePaneID, MothApplicationShellScene.secondaryPaneID)
        XCTAssertEqual(scene.bufferSnapshot.text, "abc")
        XCTAssertEqual(scene.primaryView.caret, primaryBefore.caret)
        XCTAssertEqual(scene.primaryView.selection, primaryBefore.selection)
        XCTAssertEqual(
            scene.secondaryView.viewport.firstVisibleLine,
            secondaryViewportBefore.firstVisibleLine
        )
        XCTAssertEqual(
            scene.secondaryView.viewport.horizontalUTF8Column,
            secondaryViewportBefore.horizontalUTF8Column
        )
    }

    func testSaveCheckpointCanBeReachedByUndoAndRedoWithoutClearingHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MothApplicationHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("checkpoint.txt")

        var scene = MothApplicationShellScene(initialText: "")
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "saved")),
            framebufferSize: size
        )
        _ = try scene.saveDocumentAs(to: destination)
        XCTAssertFalse(scene.documentSnapshot.isDirty)
        XCTAssertTrue(scene.historyStatus.canUndo)

        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "!")),
            framebufferSize: size
        )
        XCTAssertTrue(scene.documentSnapshot.isDirty)

        _ = scene.undoDocument()
        XCTAssertEqual(scene.bufferSnapshot.text, "saved")
        XCTAssertFalse(scene.documentSnapshot.isDirty)

        _ = scene.undoDocument()
        XCTAssertEqual(scene.bufferSnapshot.text, "")
        XCTAssertTrue(scene.documentSnapshot.isDirty)

        _ = scene.redoDocument()
        XCTAssertEqual(scene.bufferSnapshot.text, "saved")
        XCTAssertFalse(scene.documentSnapshot.isDirty)
    }

    func testPointerCaptureLossBreaksTypingCoalescence() {
        var scene = MothApplicationShellScene(initialText: "")
        _ = scene.handleHostEvent(.textInput(LunaTextInputEvent(text: "a")), framebufferSize: size)
        _ = scene.handleHostEvent(.pointerCaptureLost, framebufferSize: size)
        _ = scene.handleHostEvent(.textInput(LunaTextInputEvent(text: "b")), framebufferSize: size)

        XCTAssertEqual(scene.historyStatus.undoGroupCount, 2)
        _ = scene.undoDocument()
        XCTAssertEqual(scene.bufferSnapshot.text, "a")
    }

    private func sendShortcut(
        _ key: String,
        shift: Bool = false,
        to scene: inout MothApplicationShellScene
    ) {
        _ = scene.handleHostEvent(
            .keyboard(
                LunaKeyboardEvent(
                    key: .other(key),
                    modifiers: LunaKeyboardModifiers(shift: shift, control: true)
                )
            ),
            framebufferSize: size
        )
    }
}
