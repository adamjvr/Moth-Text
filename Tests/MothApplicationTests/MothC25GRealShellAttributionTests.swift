// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
@testable import MothApplication

final class MothC25GRealShellAttributionTests: XCTestCase {
    func testRealShellReusesOneProjectionAndAttributesDamagePaths() {
        var scene = MothApplicationShellScene(initialText: "alpha\nbeta\ngamma")
        var framebuffer = LunaFramebuffer(width: 1100, height: 720)

        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.initial)
        )
        scene.render(into: &framebuffer)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .fullScene)

        let afterCold = scene.runtimeWorkAttribution
        XCTAssertEqual(afterCold.presentationBuildCount, 1)
        XCTAssertEqual(afterCold.presentationRequestCount, 1)
        XCTAssertEqual(afterCold.presentationCacheHitCount, 0)
        XCTAssertEqual(afterCold.paneSurfaceBuildCount, 2)
        XCTAssertGreaterThan(afterCold.minimapSampleCount, 0)
        XCTAssertEqual(afterCold.fullSceneFrameCount, 1)

        let editInvalidations = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "x")),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )
        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: editInvalidations
        )
        scene.render(into: &framebuffer)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .partialDamage)

        let afterEdit = scene.runtimeWorkAttribution
        XCTAssertEqual(afterEdit.presentationBuildCount, 2)
        XCTAssertEqual(afterEdit.partialDamageFrameCount, 1)
    }
}
