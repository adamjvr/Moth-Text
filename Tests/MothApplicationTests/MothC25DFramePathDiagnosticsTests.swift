// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaRender
@testable import MothApplication

final class MothC25DFramePathDiagnosticsTests: XCTestCase {
    func testShellProducesOneShotFullSceneReport() {
        var shell = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 900, height: 600)
        )
        shell.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.textInput)
        )

        var framebuffer = LunaFramebuffer(width: 900, height: 600)
        shell.render(into: &framebuffer)

        let report = shell.takeFrameRenderReport()
        XCTAssertEqual(report?.path, .fullScene)
        XCTAssertEqual(report?.invalidationClass, .inputDriven)
        XCTAssertEqual(report?.cacheMissReason, .cacheAbsent)
        XCTAssertNil(shell.takeFrameRenderReport())
    }

    func testRuntimeStatusCanExposeLunaFramePathStats() {
        var stats = LunaFrameTimingStats()
        stats.record(
            LunaFrameTimingSample(
                frameIndex: 1,
                startedAtNanoseconds: 0,
                totalNanoseconds: 1,
                renderReport: LunaFrameRenderReport(
                    path: .fullScene,
                    invalidationClass: .initial,
                    cacheMissReason: .notApplicable
                )
            )
        )

        var shell = MothApplicationShellScene()
        shell.updateHostRuntimeDiagnostics(
            timingStats: stats,
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.initial)
        )

        XCTAssertTrue(shell.runtimePerformanceDiagnostics.contains("path fullScene"))
    }
}
