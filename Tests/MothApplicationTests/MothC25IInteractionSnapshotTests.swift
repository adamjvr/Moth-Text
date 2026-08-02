// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
@testable import MothApplication

final class MothC25IInteractionSnapshotTests: XCTestCase {
    func testFullRenderSharesOnePresentationRequestAcrossPanesAndMinimap() {
        let text = (0..<50_000)
            .map { "line \($0) payload" }
            .joined(separator: "\n")
        var scene = MothApplicationShellScene(initialText: text)
        var framebuffer = LunaFramebuffer(width: 1100, height: 720)

        let before = scene.runtimeWorkAttribution
        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.initial)
        )
        scene.render(into: &framebuffer)
        let after = scene.runtimeWorkAttribution

        XCTAssertEqual(
            after.presentationRequestCount - before.presentationRequestCount,
            1
        )
        XCTAssertEqual(
            after.presentationBuildCount - before.presentationBuildCount,
            1
        )
        XCTAssertGreaterThanOrEqual(
            after.paneSurfaceBuildCount - before.paneSurfaceBuildCount,
            2
        )
        XCTAssertEqual(after.schemaVersion, 4)
    }

    func testPointerInteractionBuildsOneReusablePaneSnapshot() {
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
    }

    func testIconAndDesktopIntegrationAssetsArePresent() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let icon = root.appendingPathComponent(
            "packaging/linux/hicolor/256x256/apps/"
                + "io.github.adamjvr.MothText.png"
        )
        let desktop = root.appendingPathComponent(
            "packaging/linux/io.github.adamjvr.MothText.desktop"
        )
        let installer = root.appendingPathComponent(
            "packaging/linux/install-user.sh"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: icon.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktop.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.path))
    }
}
