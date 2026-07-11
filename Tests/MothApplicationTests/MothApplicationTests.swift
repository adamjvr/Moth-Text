// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
@testable import MothApplication

final class MothApplicationTests: XCTestCase {
    func testShellSceneIsInvalidationDrivenAndTracksResize() {
        var scene = MothApplicationShellScene()
        XCTAssertFalse(scene.wantsContinuousRendering)

        let resized = LunaSizeI(width: 1440, height: 900)
        let invalidations = scene.handleHostEvent(
            .windowResized(resized),
            framebufferSize: resized
        )

        XCTAssertEqual(scene.framebufferSize, resized)
        XCTAssertTrue(invalidations.reasons.contains(.windowResized))
    }

    func testPointerPressChangesVisibleAccentState() {
        var scene = MothApplicationShellScene()
        let size = LunaSizeI(width: 1100, height: 720)
        let event = LunaPointerEvent(
            phase: .down,
            location: LunaPointI(x: 100, y: 100),
            button: .primary
        )

        let before = scene.pointerAccentIsActive
        let invalidations = scene.handleHostEvent(
            .pointer(event),
            framebufferSize: size
        )

        XCTAssertNotEqual(scene.pointerAccentIsActive, before)
        XCTAssertTrue(invalidations.reasons.contains(.input))
    }

    func testShellRendersDistinctChromeAndEditorPixels() {
        var scene = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 800, height: 600)
        )
        var framebuffer = LunaFramebuffer(width: 800, height: 600)

        scene.render(into: &framebuffer)

        func pixel(atX x: Int, y: Int) -> [UInt8] {
            var result: [UInt8] = []
            framebuffer.withUnsafePixelBytes { pointer, stride in
                let start = pointer.advanced(by: y * stride + x * 4)
                result = Array(UnsafeBufferPointer(start: start, count: 4))
            }
            return result
        }

        XCTAssertNotEqual(pixel(atX: 10, y: 10), pixel(atX: 400, y: 300))
        XCTAssertNotEqual(pixel(atX: 10, y: 100), pixel(atX: 400, y: 300))
    }
}
