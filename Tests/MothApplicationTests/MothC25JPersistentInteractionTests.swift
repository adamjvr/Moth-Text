// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
@testable import MothApplication

final class MothC25JPersistentInteractionTests: XCTestCase {
    func testRepeatedPointerHoverReusesSnapshotAndTargetSurface() {
        let text = (0..<50_000)
            .map { "line \($0) payload" }
            .joined(separator: "\n")
        var scene = MothApplicationShellScene(initialText: text)
        let size = LunaSizeI(width: 1100, height: 720)
        let event = LunaPointerEvent(
            phase: .moved,
            location: LunaPointI(x: 420, y: 180)
        )

        let before = scene.runtimeWorkAttribution
        let first = scene.handleHostEvent(.pointer(event), framebufferSize: size)
        let second = scene.handleHostEvent(.pointer(event), framebufferSize: size)
        let after = scene.runtimeWorkAttribution

        XCTAssertTrue(first.reasons.isEmpty)
        XCTAssertTrue(second.reasons.isEmpty)
        XCTAssertEqual(
            after.interactionSnapshotRequestCount
                - before.interactionSnapshotRequestCount,
            2
        )
        XCTAssertEqual(
            after.interactionSnapshotBuildCount
                - before.interactionSnapshotBuildCount,
            1
        )
        XCTAssertEqual(
            after.interactionSnapshotCacheHitCount
                - before.interactionSnapshotCacheHitCount,
            1
        )
        XCTAssertEqual(
            after.interactionTargetSurfaceBuildCount
                - before.interactionTargetSurfaceBuildCount,
            1
        )
        XCTAssertEqual(
            after.noRenderHostEventCount - before.noRenderHostEventCount,
            2
        )
        XCTAssertEqual(after.schemaVersion, 4)
    }

    func testCaretNavigationUsesPartialPaneDamageAfterColdFrame() {
        var scene = MothApplicationShellScene(initialText: "alpha\nbeta")
        var framebuffer = LunaFramebuffer(width: 1100, height: 720)

        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.initial)
        )
        scene.render(into: &framebuffer)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .fullScene)

        let invalidations = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(key: .arrowRight)),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )
        XCTAssertTrue(invalidations.reasons.contains(.selectionChanged))
        XCTAssertFalse(invalidations.reasons.contains(.input))

        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: invalidations
        )
        scene.render(into: &framebuffer)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .partialDamage)
    }

    func testKeyboardDeleteUsesDocumentEditDamageAfterColdFrame() {
        var scene = MothApplicationShellScene(initialText: "abc")
        var framebuffer = LunaFramebuffer(width: 1100, height: 720)

        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.initial)
        )
        scene.render(into: &framebuffer)
        _ = scene.takeFrameRenderReport()

        let invalidations = scene.handleHostEvent(
            .keyboard(LunaKeyboardEvent(key: .delete)),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )
        XCTAssertTrue(invalidations.reasons.contains(.textInput))
        XCTAssertEqual(scene.bufferSnapshot.text, "bc")

        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: invalidations
        )
        scene.render(into: &framebuffer)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .partialDamage)
    }
}
