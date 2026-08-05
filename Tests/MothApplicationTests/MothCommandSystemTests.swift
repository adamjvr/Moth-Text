// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaCommands
import LunaCore
import LunaHostCore
import LunaInput
@testable import MothApplication
import MothTextCore
import MothWorkspace

final class MothCommandSystemTests: XCTestCase {
    private let size = LunaSizeI(width: 1100, height: 720)

    func testStableCommandVocabularyHasUniqueNamespacedIdentifiers() {
        XCTAssertEqual(MothCommandID.newFile.rawValue, "moth.file.new")
        XCTAssertEqual(MothCommandID.copy.rawValue, "moth.edit.copy")
        XCTAssertEqual(MothCommandID.replaceAll.rawValue, "moth.find.replaceAll")
        XCTAssertEqual(MothCommandID.showCommandPalette.rawValue, "moth.tools.commandPalette")
        XCTAssertEqual(Set(MothCommandID.all).count, MothCommandID.all.count)
        XCTAssertTrue(MothCommandID.all.allSatisfy { $0.rawValue.hasPrefix("moth.") })
    }

    func testDescriptorsProjectExpectedDefaultKeyBindings() {
        let scene = MothApplicationShellScene(initialText: "")
        let descriptors = Dictionary(uniqueKeysWithValues: scene.commandDescriptors.map { ($0.id, $0) })

        XCTAssertEqual(descriptors[MothCommandID.newFile]?.defaultKey, LunaKeyEquivalent("N", modifiers: [.primary]))
        XCTAssertEqual(
            descriptors[MothCommandID.saveAs]?.defaultKey,
            LunaKeyEquivalent("S", modifiers: [.primary, .shift])
        )
        XCTAssertEqual(descriptors[MothCommandID.selectAll]?.menuPath, ["Selection"])
        XCTAssertEqual(
            descriptors[MothCommandID.closeTab]?.defaultKey,
            LunaKeyEquivalent("W", modifiers: [.primary])
        )
        XCTAssertEqual(
            descriptors[MothCommandID.nextTab]?.defaultKey,
            LunaKeyEquivalent("Tab", modifiers: [.primary])
        )
        XCTAssertEqual(descriptors[MothCommandID.showCommandPalette]?.isPaletteVisible, false)
    }

    func testAvailabilityTracksHistoryDocumentAndSelectionState() throws {
        var scene = MothApplicationShellScene(initialText: "")
        XCTAssertFalse(scene.commandAvailability(for: MothCommandID.undo).isEnabled)
        XCTAssertFalse(scene.commandAvailability(for: MothCommandID.redo).isEnabled)
        XCTAssertFalse(scene.commandAvailability(for: MothCommandID.selectAll).isEnabled)
        XCTAssertTrue(
            scene.commandAvailability(for: MothCommandID.save).isEnabled,
            "Untitled Save must request Save As"
        )

        type("x", into: &scene)
        XCTAssertTrue(scene.commandAvailability(for: MothCommandID.undo).isEnabled)
        XCTAssertTrue(scene.commandAvailability(for: MothCommandID.selectAll).isEnabled)

        _ = scene.executeCommand(MothCommandID.undo)
        XCTAssertTrue(scene.commandAvailability(for: MothCommandID.redo).isEnabled)

        let file = try temporaryFile(contents: "saved")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try scene.openDocument(at: file)
        XCTAssertFalse(scene.commandAvailability(for: MothCommandID.save).isEnabled)
    }

    func testKeyboardNewFileInstallsFreshCleanDocumentAndSuppressesShortcutText() {
        var scene = MothApplicationShellScene(initialText: "old")
        let oldSheet = try! XCTUnwrap(scene.activeDocumentSheetID)
        let oldDocument = scene.documentSnapshot.id
        let oldBuffer = scene.bufferSnapshot.id

        sendShortcut("n", to: &scene)
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "n")),
            framebufferSize: size
        )

        XCTAssertEqual(scene.documentSheetCount, 2)
        XCTAssertEqual(scene.bufferSnapshot.text, "")
        XCTAssertNotEqual(scene.documentSnapshot.id, oldDocument)
        XCTAssertNotEqual(scene.bufferSnapshot.id, oldBuffer)
        XCTAssertFalse(scene.documentSnapshot.isDirty)
        XCTAssertEqual(scene.lastCommandID, MothCommandID.newFile)
        XCTAssertEqual(scene.lastCommandSource, "keyboard")
        XCTAssertTrue(scene.activateDocumentSheet(oldSheet))
        XCTAssertEqual(scene.bufferSnapshot.text, "old")
    }

    func testNewFilePreservesPaneGeometryButResetsViewsAndHistory() {
        var scene = MothApplicationShellScene(initialText: "abc")
        _ = scene.executeCommand(MothCommandID.nextPane)
        let rootBefore = scene.paneWorkspace.root

        _ = scene.executeCommand(MothCommandID.newFile)

        XCTAssertEqual(scene.documentSheetCount, 2)
        XCTAssertEqual(scene.paneWorkspace.root, rootBefore)
        XCTAssertEqual(scene.activePaneID, MothApplicationShellScene.primaryPaneID)
        XCTAssertEqual(scene.primaryView.caret, .zero)
        XCTAssertEqual(scene.secondaryView.caret, .zero)
        XCTAssertFalse(scene.historyStatus.canUndo)
        XCTAssertFalse(scene.historyStatus.canRedo)
    }

    func testDirtyNewFileDiscardReplacesDocument() {
        let dialogs = LunaScriptedDialogService(unsavedDecisions: [.discard])
        var scene = MothApplicationShellScene(initialText: "", dialogService: dialogs)
        type("dirty", into: &scene)
        let oldSheet = try! XCTUnwrap(scene.activeDocumentSheetID)

        let result = scene.executeCommand(MothCommandID.newFile)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(scene.documentSheetCount, 2)
        XCTAssertEqual(scene.bufferSnapshot.text, "")
        XCTAssertTrue(scene.activateDocumentSheet(oldSheet))
        XCTAssertEqual(scene.bufferSnapshot.text, "dirty")
        XCTAssertTrue(scene.documentSnapshot.isDirty)
    }

    func testDirtyNewFileCancelPreservesEveryDocumentIdentity() {
        let dialogs = LunaScriptedDialogService(unsavedDecisions: [.cancel])
        var scene = MothApplicationShellScene(initialText: "", dialogService: dialogs)
        type("dirty", into: &scene)
        let documentBefore = scene.documentSnapshot
        let historyBefore = scene.historyStatus
        let oldSheet = try! XCTUnwrap(scene.activeDocumentSheetID)

        let result = scene.executeCommand(MothCommandID.newFile)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(scene.documentSheetCount, 2)
        XCTAssertTrue(scene.activateDocumentSheet(oldSheet))
        XCTAssertEqual(scene.documentSnapshot.id, documentBefore.id)
        XCTAssertEqual(scene.bufferSnapshot.id, documentBefore.buffer.id)
        XCTAssertEqual(scene.bufferSnapshot.text, "dirty")
        XCTAssertEqual(scene.historyStatus.currentState, historyBefore.currentState)
    }

    func testDirtyUntitledNewFileSaveAsMustSucceedBeforeReplacement() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("should-not-save-before-new.txt")
        let dialogs = LunaScriptedDialogService(
            unsavedDecisions: [.save],
            savePathSelections: [destination.path],
            scriptedSelectionsAllowOverwrite: true
        )
        var scene = MothApplicationShellScene(initialText: "", dialogService: dialogs)
        type("preserve me", into: &scene)
        let oldSheet = try XCTUnwrap(scene.activeDocumentSheetID)

        let result = scene.executeCommand(MothCommandID.newFile)

        XCTAssertTrue(result.didHandle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(scene.bufferSnapshot.text, "")
        XCTAssertTrue(scene.activateDocumentSheet(oldSheet))
        XCTAssertEqual(scene.bufferSnapshot.text, "preserve me")
        XCTAssertTrue(scene.documentSnapshot.isDirty)
    }

    func testDirtyUntitledNewFileStopsWhenSaveAsIsUnavailable() {
        let dialogs = LunaScriptedDialogService(unsavedDecisions: [.save])
        var scene = MothApplicationShellScene(initialText: "", dialogService: dialogs)
        type("must remain", into: &scene)
        let oldSheet = try! XCTUnwrap(scene.activeDocumentSheetID)

        let result = scene.executeCommand(MothCommandID.newFile)

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(scene.documentSheetCount, 2)
        XCTAssertTrue(scene.activateDocumentSheet(oldSheet))
        XCTAssertEqual(scene.bufferSnapshot.text, "must remain")
        XCTAssertTrue(scene.documentSnapshot.isDirty)
    }

    func testSelectAllAffectsOnlyActiveView() {
        var scene = MothApplicationShellScene(initialText: "café")
        let secondaryBefore = scene.secondaryView

        _ = scene.executeCommand(MothCommandID.selectAll)

        XCTAssertEqual(scene.primaryView.selection?.normalizedRange, MothTextRange(start: 0, end: 5))
        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 5))
        XCTAssertEqual(scene.secondaryView, secondaryBefore)
    }

    func testKeyboardMenuAndProgrammaticSourcesConvergeOnSameNewFileCommand() {
        var keyboardScene = MothApplicationShellScene(initialText: "abc")
        sendShortcut("n", to: &keyboardScene)

        var menuScene = MothApplicationShellScene(initialText: "abc")
        // File top-level frame begins at x=100. Its first row begins below the
        // 30-point menu bar after the reusable dropdown padding.
        sendPointerDown(x: 112, y: 12, to: &menuScene)
        XCTAssertTrue(menuScene.isMenuOpen)
        sendPointerDown(x: 120, y: 42, to: &menuScene)

        var directScene = MothApplicationShellScene(initialText: "abc")
        _ = directScene.executeCommand(MothCommandID.newFile, source: "programmatic")

        XCTAssertEqual(keyboardScene.bufferSnapshot.text, directScene.bufferSnapshot.text)
        XCTAssertEqual(menuScene.bufferSnapshot.text, directScene.bufferSnapshot.text)
        XCTAssertEqual(menuScene.lastCommandID, MothCommandID.newFile)
        XCTAssertEqual(menuScene.lastCommandSource, "menu")
        XCTAssertFalse(menuScene.isMenuOpen)
    }

    func testCommandPaletteOwnsTextInputAndExecutesSelectAll() {
        var scene = MothApplicationShellScene(initialText: "alpha beta")
        sendShortcut("p", shift: true, to: &scene)
        XCTAssertTrue(scene.isCommandPaletteOpen)

        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "select all")),
            framebufferSize: size
        )
        XCTAssertEqual(scene.commandPaletteQuery, "select all")
        XCTAssertEqual(scene.bufferSnapshot.text, "alpha beta")

        _ = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(key: .enter)),
            framebufferSize: size
        )

        XCTAssertFalse(scene.isCommandPaletteOpen)
        XCTAssertEqual(scene.lastCommandID, MothCommandID.selectAll)
        XCTAssertEqual(scene.lastCommandSource, "palette")
        XCTAssertEqual(scene.primaryView.selection?.normalizedRange, MothTextRange(start: 0, end: 10))
    }

    func testCommandPaletteEscapeReturnsCommittedTextToEditor() {
        var scene = MothApplicationShellScene(initialText: "abc")
        sendShortcut("p", shift: true, to: &scene)
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "select")),
            framebufferSize: size
        )

        _ = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(key: .escape)),
            framebufferSize: size
        )
        XCTAssertFalse(scene.isCommandPaletteOpen)

        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "X")),
            framebufferSize: size
        )
        XCTAssertEqual(scene.bufferSnapshot.text, "Xabc")
    }

    func testPaletteFindCommandDismissesPaletteAndOpensVisiblePanel() {
        var scene = MothApplicationShellScene(initialText: "abc")
        sendShortcut("p", shift: true, to: &scene)
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "find")),
            framebufferSize: size
        )
        _ = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(key: .enter)),
            framebufferSize: size
        )

        XCTAssertFalse(scene.isCommandPaletteOpen)
        XCTAssertTrue(scene.isFindPanelOpen)
        XCTAssertEqual(scene.lastCommandID, MothCommandID.showFind)
        XCTAssertEqual(scene.lastCommandSource, "palette")
        XCTAssertEqual(scene.bufferSnapshot.text, "abc")
    }

    func testPalettePointerFindActivationOpensVisiblePanel() {
        var scene = MothApplicationShellScene(initialText: "abc")
        sendShortcut("p", shift: true, to: &scene)
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "find")),
            framebufferSize: size
        )

        _ = scene.handleHostEvent(
            .pointer(
                LunaPointerEvent(
                    phase: .down,
                    location: LunaPointI(x: 240, y: 150),
                    button: .primary
                )
            ),
            framebufferSize: size
        )

        XCTAssertFalse(scene.isCommandPaletteOpen)
        XCTAssertTrue(scene.isFindPanelOpen)
        XCTAssertEqual(scene.lastCommandID, MothCommandID.showFind)
        XCTAssertEqual(scene.lastCommandSource, "palette")
        XCTAssertEqual(scene.bufferSnapshot.text, "abc")
    }

    func testFindShortcutOpensPanelAndSuppressesShortcutText() {
        var scene = MothApplicationShellScene(initialText: "abc")
        sendShortcut("f", to: &scene)
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "f")),
            framebufferSize: size
        )

        XCTAssertEqual(scene.bufferSnapshot.text, "abc")
        XCTAssertTrue(scene.isFindPanelOpen)
        XCTAssertEqual(scene.lastCommandID, MothCommandID.showFind)
        XCTAssertEqual(scene.lastCommandSource, "keyboard")
    }

    func testUnknownCommandIsRejectedWithoutMutation() {
        var scene = MothApplicationShellScene(initialText: "abc")
        let result = scene.executeCommand("moth.unknown")
        XCTAssertFalse(result.didHandle)
        XCTAssertEqual(scene.bufferSnapshot.text, "abc")
        XCTAssertTrue(scene.statusMessage.contains("Unknown command"))
    }

    private func type(_ text: String, into scene: inout MothApplicationShellScene) {
        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: text)),
            framebufferSize: size
        )
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

    private func sendPointerDown(x: Int, y: Int, to scene: inout MothApplicationShellScene) {
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

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MothCommandSystemTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func temporaryFile(contents: String) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("document.txt")
        try Data(contents.utf8).write(to: file)
        return file
    }
}
