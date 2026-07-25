// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaRender
@testable import MothApplication

final class MothC25D2PartialDamageTests: XCTestCase {
    func testDocumentInputPlanDamagesOnlyDocumentDependentRegions() {
        let geometry = MothApplicationFrameGeometry(
            framebufferSize: LunaSizeI(width: 1_100, height: 720)
        )
        let plan = MothApplicationFrameDamagePlan.make(
            invalidations: LunaFrameInvalidationSet(.textInput),
            geometry: geometry,
            hasCompatibleCache: true,
            hasActiveOverlay: false
        )

        XCTAssertEqual(plan.kind, .documentEdit)
        XCTAssertEqual(plan.path, .partialDamage)
        XCTAssertEqual(plan.regions.count, 4)
        XCTAssertTrue(plan.regions.contains { sameRect($0, geometry.paneBounds) })
        XCTAssertTrue(plan.regions.contains { sameRect($0, geometry.minimapBounds) })
        XCTAssertFalse(plan.regions.contains { sameRect($0, geometry.sidebarBounds) })
    }

    func testOverlayAndMissingCacheForceFullScene() {
        let geometry = MothApplicationFrameGeometry(
            framebufferSize: LunaSizeI(width: 900, height: 600)
        )

        let missingCache = MothApplicationFrameDamagePlan.make(
            invalidations: LunaFrameInvalidationSet(.textInput),
            geometry: geometry,
            hasCompatibleCache: false,
            hasActiveOverlay: false
        )
        XCTAssertEqual(missingCache.path, .fullScene)
        XCTAssertEqual(missingCache.cacheMissReason, .cacheAbsent)

        let overlay = MothApplicationFrameDamagePlan.make(
            invalidations: LunaFrameInvalidationSet(.scrollChanged),
            geometry: geometry,
            hasCompatibleCache: true,
            hasActiveOverlay: true
        )
        XCTAssertEqual(overlay.path, .fullScene)
        XCTAssertEqual(overlay.cacheMissReason, .transientOverlayActive)
    }

    private func sameRect(_ lhs: LunaRectI, _ rhs: LunaRectI) -> Bool {
        lhs.x == rhs.x
            && lhs.y == rhs.y
            && lhs.w == rhs.w
            && lhs.h == rhs.h
    }

    func testShellTransitionsFromFullSceneToPartialTextDamage() {
        var shell = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 900, height: 600)
        )
        var framebuffer = LunaFramebuffer(width: 900, height: 600)

        shell.render(into: &framebuffer)
        XCTAssertEqual(shell.takeFrameRenderReport()?.path, .fullScene)

        shell.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.textInput)
        )
        shell.render(into: &framebuffer)

        let report = shell.takeFrameRenderReport()
        XCTAssertEqual(report?.path, .partialDamage)
        XCTAssertEqual(report?.invalidationClass, .inputDriven)
        XCTAssertEqual(report?.damagedRegionCount, 4)
        XCTAssertGreaterThan(report?.damagedPixelCount ?? 0, 0)
        XCTAssertNil(shell.takeFrameRenderReport())
    }
}
