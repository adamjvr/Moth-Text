// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaCommands
import LunaCore
import LunaHostCore
import LunaInput
@testable import MothApplication

final class MothM3ADocumentSheetTests: XCTestCase {
    private let size = LunaSizeI(width: 1100, height: 720)

    func testNewFileAppendsAndActivatesWithoutReplacingDirtyDocument() {
        let dialogs = LunaScriptedDialogService(unsavedDecisions: [.cancel])
        var scene = MothApplicationShellScene(
            initialText: "original",
            dialogService: dialogs
        )
        let originalID = try! XCTUnwrap(scene.activeDocumentSheetID)
        type("!", into: &scene)

        let result = scene.executeCommand(MothCommandID.newFile)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(scene.documentSheetCount, 2)
        XCTAssertNotEqual(scene.activeDocumentSheetID, originalID)
        XCTAssertEqual(scene.bufferSnapshot.text, "")
        XCTAssertTrue(scene.activateDocumentSheet(originalID))
        XCTAssertEqual(scene.bufferSnapshot.text, "!original")
        XCTAssertTrue(scene.documentSnapshot.isDirty)
    }

    func testSwitchingSheetsRestoresIndependentDocumentsAndPaneViews() {
        var scene = MothApplicationShellScene(initialText: "alpha")
        let firstID = try! XCTUnwrap(scene.activeDocumentSheetID)
        type("A", into: &scene)
        let firstPrimary = scene.primaryView

        _ = scene.executeCommand(MothCommandID.newFile)
        let secondID = try! XCTUnwrap(scene.activeDocumentSheetID)
        type("B", into: &scene)
        let secondPrimary = scene.primaryView

        XCTAssertTrue(scene.activateDocumentSheet(firstID))
        XCTAssertEqual(scene.bufferSnapshot.text, "Aalpha")
        XCTAssertEqual(scene.primaryView, firstPrimary)

        XCTAssertTrue(scene.activateDocumentSheet(secondID))
        XCTAssertEqual(scene.bufferSnapshot.text, "B")
        XCTAssertEqual(scene.primaryView, secondPrimary)
    }

    func testOpeningCanonicalFileTwiceReusesExistingSheet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MothM3AOpen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("same.txt")
        try Data("same document".utf8).write(to: file)

        var scene = MothApplicationShellScene(initialText: "initial")
        try scene.openDocument(at: file)
        let openedID = scene.activeDocumentSheetID
        XCTAssertEqual(scene.documentSheetCount, 2)

        try scene.openDocument(at: directory.appendingPathComponent("./same.txt"))

        XCTAssertEqual(scene.documentSheetCount, 2)
        XCTAssertEqual(scene.activeDocumentSheetID, openedID)
        XCTAssertEqual(scene.bufferSnapshot.text, "same document")
    }

    func testDirtyCloseCancelPreservesOnlyTargetedSheet() {
        let dialogs = LunaScriptedDialogService(unsavedDecisions: [.cancel])
        var scene = MothApplicationShellScene(initialText: "first", dialogService: dialogs)
        _ = scene.executeCommand(MothCommandID.newFile)
        let dirtyID = scene.activeDocumentSheetID
        type("dirty", into: &scene)

        let result = scene.executeCommand(MothCommandID.closeTab)

        XCTAssertFalse(result.didHandle)
        XCTAssertEqual(scene.documentSheetCount, 2)
        XCTAssertEqual(scene.activeDocumentSheetID, dirtyID)
        XCTAssertEqual(scene.bufferSnapshot.text, "dirty")
    }

    func testDirtyCloseDiscardRemovesOnlyActiveSheet() {
        let dialogs = LunaScriptedDialogService(unsavedDecisions: [.discard])
        var scene = MothApplicationShellScene(initialText: "first", dialogService: dialogs)
        let firstID = scene.activeDocumentSheetID
        _ = scene.executeCommand(MothCommandID.newFile)
        type("dirty", into: &scene)

        let result = scene.executeCommand(MothCommandID.closeTab)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(scene.documentSheetCount, 1)
        XCTAssertEqual(scene.activeDocumentSheetID, firstID)
        XCTAssertEqual(scene.bufferSnapshot.text, "first")
    }

    func testClosingFinalSheetCreatesFreshUntitledSheet() {
        var scene = MothApplicationShellScene(initialText: "")
        let oldID = scene.activeDocumentSheetID

        XCTAssertTrue(scene.closeActiveDocumentSheet())

        XCTAssertEqual(scene.documentSheetCount, 1)
        XCTAssertNotEqual(scene.activeDocumentSheetID, oldID)
        XCTAssertTrue(scene.documentSnapshot.isUntitled)
        XCTAssertEqual(scene.bufferSnapshot.text, "")
    }

    func testControlTabTraversesDocumentSheetsAndControlAltTabTraversesPanes() {
        var scene = MothApplicationShellScene(initialText: "first")
        let firstID = scene.activeDocumentSheetID
        _ = scene.executeCommand(MothCommandID.newFile)
        let secondID = scene.activeDocumentSheetID

        sendKey(.tab, modifiers: LunaKeyboardModifiers(shift: true, control: true), to: &scene)
        XCTAssertEqual(scene.activeDocumentSheetID, firstID)

        sendKey(.tab, modifiers: LunaKeyboardModifiers(control: true), to: &scene)
        XCTAssertEqual(scene.activeDocumentSheetID, secondID)

        XCTAssertEqual(scene.activePaneID, MothApplicationShellScene.primaryPaneID)
        sendKey(
            .tab,
            modifiers: LunaKeyboardModifiers(control: true, option: true),
            to: &scene
        )
        XCTAssertEqual(scene.activePaneID, MothApplicationShellScene.secondaryPaneID)
    }

    func testPointerTabActivationAndCloseUseStableSheetTargets() throws {
        var scene = MothApplicationShellScene(initialText: "first")
        let firstID = try XCTUnwrap(scene.activeDocumentSheetID)
        _ = scene.executeCommand(MothCommandID.newFile)
        let secondID = try XCTUnwrap(scene.activeDocumentSheetID)
        let firstFrame = try XCTUnwrap(
            scene.documentTabLayout().tabFrames.first {
                $0.tab.id.rawValue == firstID.rawValue
            }
        )

        sendPointer(
            .down,
            x: firstFrame.bounds.x + firstFrame.bounds.w / 2,
            y: firstFrame.bounds.y + firstFrame.bounds.h / 2,
            to: &scene
        )
        XCTAssertEqual(scene.activeDocumentSheetID, firstID)

        let refreshed = try XCTUnwrap(
            scene.documentTabLayout().tabFrames.first {
                $0.tab.id.rawValue == firstID.rawValue
            }
        )
        let close = try XCTUnwrap(refreshed.closeButtonBounds)
        let x = close.x + max(1, close.w / 2)
        let y = close.y + max(1, close.h / 2)
        sendPointer(.down, x: x, y: y, to: &scene)
        sendPointer(.up, x: x, y: y, to: &scene)

        XCTAssertEqual(scene.documentSheetCount, 1)
        XCTAssertEqual(scene.activeDocumentSheetID, secondID)
    }

    func testOpenFilesSidebarActivatesTheSameStableSheetAsTabs() throws {
        var scene = MothApplicationShellScene(initialText: "first")
        let firstID = try XCTUnwrap(scene.activeDocumentSheetID)
        _ = scene.executeCommand(MothCommandID.newFile)
        let secondID = try XCTUnwrap(scene.activeDocumentSheetID)
        XCTAssertNotEqual(firstID, secondID)

        let firstRow = try XCTUnwrap(
            scene.openFilesLayout().sidebarRows.first {
                $0.item.id.rawValue == firstID.rawValue
            }
        )
        sendPointer(
            .down,
            x: firstRow.bounds.x + max(1, firstRow.bounds.w / 2),
            y: firstRow.bounds.y + max(1, firstRow.bounds.h / 2),
            to: &scene
        )

        XCTAssertEqual(scene.activeDocumentSheetID, firstID)
        XCTAssertEqual(scene.bufferSnapshot.text, "first")
    }

    func testTabLayoutReportsDeterministicOverflowAndKeepsActiveVisible() {
        var scene = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 640, height: 480),
            initialText: "first"
        )
        for _ in 0..<12 {
            _ = scene.executeCommand(MothCommandID.newFile)
        }

        let layout = scene.documentTabLayout()
        XCTAssertFalse(layout.hiddenTabIDs.isEmpty)
        XCTAssertNotNil(layout.tabOverflowButtonBounds)
        XCTAssertTrue(
            layout.tabFrames.contains {
                $0.tab.id.rawValue == scene.activeDocumentSheetID?.rawValue
            }
        )
    }

    private func type(_ text: String, into scene: inout MothApplicationShellScene) {
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: text)),
            framebufferSize: size
        )
    }

    private func sendKey(
        _ key: LunaKeyboardKey,
        modifiers: LunaKeyboardModifiers,
        to scene: inout MothApplicationShellScene
    ) {
        _ = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(key: key, modifiers: modifiers)),
            framebufferSize: scene.framebufferSize
        )
    }

    private func sendPointer(
        _ phase: LunaPointerPhase,
        x: Int,
        y: Int,
        to scene: inout MothApplicationShellScene
    ) {
        _ = scene.handleHostEvent(
            .pointer(
                LunaPointerEvent(
                    phase: phase,
                    location: LunaPointI(x: x, y: y),
                    button: .primary
                )
            ),
            framebufferSize: scene.framebufferSize
        )
    }
}
