// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaUI
import MothTextCore
@testable import MothApplication

final class MothC25HLargeDocumentPathTests: XCTestCase {
    func testFiftyThousandLineMinimapSamplesUseIndexedMetadata() throws {
        let text = (0..<50_000)
            .map { "line \($0) abcdefghijklmnopqrstuvwxyz" }
            .joined(separator: "\n")
        let buffer = MothInMemorySourceBuffer(text: text)
        let document = MothLunaTextStorageAdapter(buffer: buffer)
            .textSnapshot()
            .staticDocument
        let plan = MothMinimapSamplePlan(
            logicalLineCount: document.lineCount,
            activeLogicalLineIndex: 25_000,
            availableHeight: 600,
            rowStride: 6
        )

        let metadata = plan.samples.compactMap {
            document.lineMetadata(at: $0.logicalLineIndex)
        }

        XCTAssertEqual(document.lineCount, 50_000)
        XCTAssertEqual(metadata.count, plan.samples.count)
        XCTAssertEqual(metadata.first?.index, 0)
        XCTAssertEqual(metadata.last?.index, 49_999)
        XCTAssertTrue(metadata.allSatisfy { $0.utf8Length > 0 })
    }

    func testRealShellAttributesMetadataOnlyMinimapLookups() {
        let text = (0..<50_000)
            .map { "line \($0) payload" }
            .joined(separator: "\n")
        var scene = MothApplicationShellScene(initialText: text)
        var framebuffer = LunaFramebuffer(width: 1100, height: 720)

        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.initial)
        )
        scene.render(into: &framebuffer)

        let snapshot = scene.runtimeWorkAttribution
        XCTAssertEqual(snapshot.schemaVersion, 3)
        XCTAssertGreaterThan(snapshot.minimapSampleCount, 0)
        XCTAssertEqual(
            snapshot.minimapMetadataLookupCount,
            snapshot.minimapSampleCount
        )
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .fullScene)
    }

    func testLargeDocumentEditStillUsesPartialDamage() {
        let text = (0..<50_000)
            .map { "line \($0) payload" }
            .joined(separator: "\n")
        var scene = MothApplicationShellScene(initialText: text)
        var framebuffer = LunaFramebuffer(width: 1100, height: 720)

        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.initial)
        )
        scene.render(into: &framebuffer)
        _ = scene.takeFrameRenderReport()

        let invalidations = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "x")),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )
        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: invalidations
        )
        scene.render(into: &framebuffer)

        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .partialDamage)
        XCTAssertGreaterThanOrEqual(
            scene.runtimeWorkAttribution.presentationBuildCount,
            2
        )
    }
}
