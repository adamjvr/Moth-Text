// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
@testable import MothApplication
import MothEditor
import MothTextCore

final class MothGraphemeInteractionTests: XCTestCase {
    private let size = LunaSizeI(width: 1100, height: 720)
    private let text = "Ae\u{301}Z"

    func testArrowNavigationMovesAcrossExtendedGraphemeBoundaries() {
        var scene = MothApplicationShellScene(initialText: text)

        sendKey(.arrowRight, to: &scene)
        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 1))

        sendKey(.arrowRight, to: &scene)
        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 4))

        sendKey(.arrowLeft, to: &scene)
        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 1))
    }

    func testShiftArrowSelectsOneWholeExtendedGrapheme() {
        var scene = MothApplicationShellScene(initialText: text)
        sendKey(.arrowRight, to: &scene)
        sendKey(.arrowRight, shift: true, to: &scene)

        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 4))
        XCTAssertEqual(
            scene.primaryView.selection,
            MothTextSelection(
                anchor: MothTextOffset(rawValue: 1),
                focus: MothTextOffset(rawValue: 4)
            )
        )
    }

    func testPointerPlacementUsesWholeExtendedGraphemeBoundaries() throws {
        var scene = MothApplicationShellScene(initialText: text)
        let textView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let row = try XCTUnwrap(textView.layout().visibleLines.first)
        let pointAfterCombinedCharacter = LunaPointI(
            x: row.textBounds.x + textView.metrics.glyphMetrics.advance * 2,
            y: row.rowBounds.y + row.rowBounds.h / 2
        )

        sendPointer(.down, at: pointAfterCombinedCharacter, to: &scene)
        sendPointer(.up, at: pointAfterCombinedCharacter, to: &scene)

        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 4))
    }

    func testBackspaceRemovesOneWholeExtendedGraphemeAndUndoRestoresIt() {
        var scene = MothApplicationShellScene(initialText: text)
        sendKey(.arrowRight, to: &scene)
        sendKey(.arrowRight, to: &scene)
        sendKey(.backspace, to: &scene)

        XCTAssertEqual(scene.bufferSnapshot.text, "AZ")
        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 1))

        _ = scene.undoDocument()
        XCTAssertEqual(scene.bufferSnapshot.text, text)
        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 4))
    }

    func testDeleteForwardRemovesOneWholeExtendedGraphemeAndUndoRestoresIt() {
        var scene = MothApplicationShellScene(initialText: text)
        sendKey(.arrowRight, to: &scene)
        sendKey(.delete, to: &scene)

        XCTAssertEqual(scene.bufferSnapshot.text, "AZ")
        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 1))

        _ = scene.undoDocument()
        XCTAssertEqual(scene.bufferSnapshot.text, text)
        XCTAssertEqual(scene.primaryView.caret, MothTextOffset(rawValue: 1))
    }

    private func sendPointer(
        _ phase: LunaPointerPhase,
        at location: LunaPointI,
        to scene: inout MothApplicationShellScene
    ) {
        _ = scene.handleHostEvent(
            .pointer(
                LunaPointerEvent(
                    phase: phase,
                    location: location,
                    button: .primary
                )
            ),
            framebufferSize: size
        )
    }

    private func sendKey(
        _ key: LunaKeyboardKey,
        shift: Bool = false,
        to scene: inout MothApplicationShellScene
    ) {
        _ = scene.handleHostEvent(
            .keyboard(
                LunaKeyboardEvent(
                    key: key,
                    modifiers: LunaKeyboardModifiers(shift: shift)
                )
            ),
            framebufferSize: size
        )
    }
}
