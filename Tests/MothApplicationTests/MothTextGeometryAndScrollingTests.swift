// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaUI
@testable import MothApplication
import MothTextCore

final class MothTextGeometryAndScrollingTests: XCTestCase {
    private let size = LunaSizeI(width: 1100, height: 720)

    func testRapidCommittedInputKeepsCaretOnExactShapedInsertionPosition() throws {
        var scene = MothApplicationShellScene(initialText: "")
        let rapidText = String(repeating: "rapid typing ", count: 12) + "cafe\u{301}"

        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: rapidText)),
            framebufferSize: size
        )

        XCTAssertEqual(scene.bufferSnapshot.text, rapidText)
        XCTAssertEqual(scene.primaryView.caret.rawValue, rapidText.utf8.count)
        try assertCaretUsesRowGeometry(in: scene, paneID: MothApplicationShellScene.primaryPaneID)
    }

    func testRepeatedFastInputKeepsCaretOnExactShapedInsertionPosition() throws {
        var scene = MothApplicationShellScene(initialText: "")
        for _ in 0..<120 {
            _ = scene.handleHostEvent(
                .textInput(LunaTextInputEvent(text: "x")),
                framebufferSize: size
            )
        }

        XCTAssertEqual(scene.primaryView.caret.rawValue, 120)
        try assertCaretUsesRowGeometry(in: scene, paneID: MothApplicationShellScene.primaryPaneID)
    }

    func testTabExpansionUsesColumnAlignedStopsAndPreservesSourceBoundaries() {
        let geometry = MothUnicodeTextPainter.geometry(for: "ab\tc")

        XCTAssertEqual(geometry.sourceText, "ab\tc")
        XCTAssertEqual(geometry.renderedText, "ab  c")
        XCTAssertEqual(geometry.insertionPositions.map(\.utf8Offset), [0, 1, 2, 3, 4])
        XCTAssertGreaterThan(
            geometry.x26Dot6(forUTF8Offset: 3),
            geometry.x26Dot6(forUTF8Offset: 2)
        )
    }

    func testWrappedTabGeometryPreservesLogicalLineTabStops() {
        let line = "aaaaa\tb"
        let geometry = MothUnicodeTextPainter.geometry(
            for: LunaStaticTextGeometryRequest(
                completeLineText: line,
                utf8Range: 5..<line.utf8.count
            )
        )

        XCTAssertEqual(geometry.sourceText, "\tb")
        XCTAssertEqual(geometry.renderedText, "   b")
        XCTAssertEqual(geometry.insertionPositions.map(\.utf8Offset), [0, 1, 2])
    }

    func testWheelScrollMovesHoveredSecondaryPaneWithoutChangingActivePane() throws {
        let text = (0..<200).map { "line \($0)" }.joined(separator: "\n")
        var scene = MothApplicationShellScene(initialText: text)
        let primaryBefore = scene.primaryView.viewport
        let secondaryBefore = scene.secondaryView.viewport
        let secondaryView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.secondaryPaneID)
        )
        let point = LunaPointI(
            x: secondaryView.bounds.x + secondaryView.bounds.w / 2,
            y: secondaryView.bounds.y + secondaryView.bounds.h / 2
        )

        let invalidations = scene.handleHostEvent(
            .scroll(
                LunaScrollEvent(
                    location: point,
                    deltaY: 1,
                    isPrecise: false
                )
            ),
            framebufferSize: size
        )

        XCTAssertTrue(invalidations.reasons.contains(.scrollChanged))
        XCTAssertEqual(scene.activePaneID, MothApplicationShellScene.primaryPaneID)
        XCTAssertEqual(scene.primaryView.viewport, primaryBefore)
        XCTAssertGreaterThan(
            scene.secondaryView.viewport.firstVisibleVisualRow ?? 0,
            secondaryBefore.firstVisibleVisualRow ?? 0
        )
    }

    func testPreciseScrollRemainderAccumulatesPerPane() throws {
        let text = (0..<100).map { "line \($0)" }.joined(separator: "\n")
        var scene = MothApplicationShellScene(initialText: text)
        let primaryView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let point = LunaPointI(
            x: primaryView.bounds.x + 20,
            y: primaryView.bounds.y + 20
        )

        _ = scene.handleHostEvent(
            .scroll(LunaScrollEvent(location: point, deltaY: 0.4, isPrecise: true)),
            framebufferSize: size
        )
        XCTAssertEqual(scene.primaryView.viewport.firstVisibleVisualRow, 0)
        XCTAssertEqual(
            scene.primaryView.viewport.verticalScrollRemainder,
            0.4,
            accuracy: 0.0001
        )

        _ = scene.handleHostEvent(
            .scroll(LunaScrollEvent(location: point, deltaY: 0.7, isPrecise: true)),
            framebufferSize: size
        )
        XCTAssertEqual(scene.primaryView.viewport.firstVisibleVisualRow, 1)
        XCTAssertEqual(
            scene.primaryView.viewport.verticalScrollRemainder,
            0.1,
            accuracy: 0.0001
        )
    }

    func testScrollbarLaneAndThumbRouteThroughPaneLocalViewport() throws {
        let text = (0..<200).map { "line \($0)" }.joined(separator: "\n")
        var scene = MothApplicationShellScene(initialText: text)
        let view = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let layout = view.layout()
        let thumb = try XCTUnwrap(layout.scrollbarThumbBounds)
        let lane = layout.scrollbarLaneBounds

        sendPointer(
            .down,
            at: LunaPointI(
                x: lane.x + max(0, lane.w / 2),
                y: min(lane.y + lane.h - 1, thumb.y + thumb.h + 8)
            ),
            to: &scene
        )
        XCTAssertGreaterThan(scene.primaryView.viewport.firstVisibleVisualRow ?? 0, 0)

        let updatedView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let updatedLayout = updatedView.layout()
        let updatedThumb = try XCTUnwrap(updatedLayout.scrollbarThumbBounds)
        sendPointer(
            .down,
            at: LunaPointI(x: updatedThumb.x + 1, y: updatedThumb.y + 1),
            to: &scene
        )
        XCTAssertTrue(scene.wantsPointerCapture)

        sendPointer(
            .moved,
            at: LunaPointI(x: updatedThumb.x + 1, y: updatedLayout.scrollbarLaneBounds.y + updatedLayout.scrollbarLaneBounds.h),
            to: &scene
        )
        XCTAssertEqual(
            scene.primaryView.viewport.firstVisibleVisualRow,
            updatedLayout.maxScrollTopVisualRow
        )

        sendPointer(
            .up,
            at: LunaPointI(x: updatedThumb.x + 1, y: updatedThumb.y + 1),
            to: &scene
        )
        XCTAssertFalse(scene.wantsPointerCapture)
    }

    func testCaretIsPaintedAfterGlyphsAtComputedAbsoluteCoordinate() throws {
        var scene = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 800, height: 500),
            initialText: "MMMMMMMMMMMM"
        )
        for _ in 0..<8 {
            _ = scene.handleHostEvent(
                .keyboard(LunaKeyboardEvent(key: .arrowRight)),
                framebufferSize: LunaSizeI(width: 800, height: 500)
            )
        }

        let view = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let caret = try XCTUnwrap(view.layout().caretRect)
        var framebuffer = LunaFramebuffer(width: 800, height: 500)
        scene.render(into: &framebuffer)

        let pixel = pixel(in: framebuffer, x: caret.x, y: caret.y + caret.h / 2)
        let caretColor = LunaEditorVisualStyle(theme: MothApplicationTheme.theme).caret
        XCTAssertEqual(pixel, [caretColor.b, caretColor.g, caretColor.r, caretColor.a])
    }

    private func assertCaretUsesRowGeometry(
        in scene: MothApplicationShellScene,
        paneID: LunaPaneID
    ) throws {
        let view = try XCTUnwrap(scene.paneTextView(for: paneID))
        let layout = view.layout()
        let caret = try XCTUnwrap(layout.caretRect)
        let location = view.document.location(
            forAbsoluteUTF8Offset: paneID == MothApplicationShellScene.secondaryPaneID
                ? scene.secondaryView.caret.rawValue
                : scene.primaryView.caret.rawValue
        )
        let row = try XCTUnwrap(layout.visibleLines.last(where: { visible in
            visible.line.index == location.lineIndex
                && location.utf8Column >= visible.startUTF8Column
                && location.utf8Column <= visible.endUTF8Column
        }))
        let localOffset = location.utf8Column - row.startUTF8Column
        XCTAssertEqual(
            caret.x,
            row.textBounds.x + row.rowGeometry.x(forUTF8Offset: localOffset)
        )
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

    private func pixel(in framebuffer: LunaFramebuffer, x: Int, y: Int) -> [UInt8] {
        var result: [UInt8] = []
        framebuffer.withUnsafePixelBytes { pointer, stride in
            let start = pointer.advanced(by: y * stride + x * 4)
            result = Array(UnsafeBufferPointer(start: start, count: 4))
        }
        return result
    }
}
