// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
@testable import MothApplication

final class MothC25ERuntimeFairnessTests: XCTestCase {
    func testSlicedTextDispatchPreservesDocumentOrderAndPartialDamage() throws {
        let size = LunaSizeI(width: 1_100, height: 720)
        var scene = MothApplicationShellScene(
            initialSize: size,
            initialText: "seed"
        )
        var framebuffer = LunaFramebuffer(width: size.width, height: size.height)

        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.initial)
        )
        scene.render(into: &framebuffer)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .fullScene)

        let payload = (0..<65).map { String($0 % 10) }.joined()
        let events = payload.map { character in
            LunaHostInputEvent.textInput(
                LunaTextInputEvent(text: String(character))
            )
        }
        var cursor = LunaScheduledInputDispatchCursor(
            batch: LunaScheduledInputBatch(
                events: events,
                oldestEventNanoseconds: 100,
                newestEventNanoseconds: 200,
                containsOrderingBarrier: false,
                containsPromptDispatchEvent: false,
                containsImmediateControlEvent: false,
                stats: LunaInputCoalescingStats(
                    receivedEventCount: events.count,
                    emittedEventCount: events.count,
                    receivedTextInputEventCount: events.count,
                    emittedTextInputEventCount: events.count,
                    receivedTextInputUTF8ByteCount: payload.utf8.count
                )
            )
        )
        let budget = LunaInputDispatchBudget(
            maximumSemanticEventCount: 8,
            maximumDispatchNanoseconds: 1_000_000
        )
        var renderedSliceCount = 0

        while cursor.hasPendingEvents {
            var invalidations = LunaFrameInvalidationSet()
            _ = cursor.dispatchNextSlice(
                budget: budget,
                nowNanoseconds: { 1_000 }
            ) { event in
                invalidations.formUnion(
                    scene.handleHostEvent(event, framebufferSize: size)
                )
                return LunaInputDispatchDecision.continueDispatch
            }

            scene.updateHostRuntimeDiagnostics(
                timingStats: LunaFrameTimingStats(),
                inputStats: cursor.inputStats,
                invalidations: invalidations
            )
            scene.render(into: &framebuffer)
            let report = try XCTUnwrap(scene.takeFrameRenderReport())
            XCTAssertEqual(report.path, .partialDamage)
            XCTAssertGreaterThan(report.damagedRegionCount, 0)
            XCTAssertGreaterThan(report.damagedPixelCount, 0)
            renderedSliceCount += 1
        }

        XCTAssertGreaterThan(renderedSliceCount, 1)
        XCTAssertEqual(scene.bufferSnapshot.text, payload + "seed")
        XCTAssertTrue(scene.documentSnapshot.isDirty)
        XCTAssertEqual(scene.primaryView.caret.rawValue, payload.utf8.count)
        XCTAssertEqual(
            scene.secondaryView.caret.rawValue,
            (payload + "seed").utf8.count
        )
        XCTAssertEqual(
            cursor.inputStats.dispatchedSemanticEventCount,
            events.count
        )
        XCTAssertEqual(cursor.inputStats.deferredSemanticEventCount, 0)

        XCTAssertNotNil(scene.undoDocument())
        XCTAssertEqual(scene.bufferSnapshot.text, "seed")
    }

    func testOneEventSlicesPreserveCommandBarrierOrder() {
        let size = LunaSizeI(width: 800, height: 600)
        var scene = MothApplicationShellScene(
            initialSize: size,
            initialText: ""
        )
        let events: [LunaHostInputEvent] = [
            .textInput(LunaTextInputEvent(text: "A")),
            .keyboard(
                LunaKeyboardEvent(
                    key: .arrowLeft,
                    modifiers: .none,
                    isRepeat: false
                )
            ),
            .textInput(LunaTextInputEvent(text: "B")),
        ]
        var cursor = LunaScheduledInputDispatchCursor(
            batch: LunaScheduledInputBatch(
                events: events,
                oldestEventNanoseconds: 1,
                newestEventNanoseconds: 3,
                containsOrderingBarrier: true,
                containsPromptDispatchEvent: true,
                containsImmediateControlEvent: false,
                stats: LunaInputCoalescingStats(
                    receivedEventCount: 3,
                    emittedEventCount: 3,
                    receivedTextInputEventCount: 2,
                    emittedTextInputEventCount: 2,
                    receivedTextInputUTF8ByteCount: 2,
                    emittedBarrierCount: 1
                )
            )
        )

        while cursor.hasPendingEvents {
            _ = cursor.dispatchNextSlice(
                budget: LunaInputDispatchBudget(
                    maximumSemanticEventCount: 1,
                    maximumDispatchNanoseconds: 1_000
                ),
                nowNanoseconds: { 0 }
            ) { event in
                _ = scene.handleHostEvent(event, framebufferSize: size)
                return LunaInputDispatchDecision.continueDispatch
            }
        }

        XCTAssertEqual(scene.bufferSnapshot.text, "BA")
        XCTAssertEqual(cursor.inputStats.dispatchSliceCount, 3)
    }

    func testOverlayAndResizeForceFullSceneBeforePartialWorkResumes() throws {
        let initialSize = LunaSizeI(width: 900, height: 600)
        var scene = MothApplicationShellScene(
            initialSize: initialSize,
            initialText: "seed"
        )
        var framebuffer = LunaFramebuffer(
            width: initialSize.width,
            height: initialSize.height
        )

        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.initial)
        )
        scene.render(into: &framebuffer)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .fullScene)

        _ = scene.executeCommand(
            MothCommandID.showCommandPalette,
            source: "c2.5e.test"
        )
        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: LunaFrameInvalidationSet(.input)
        )
        scene.render(into: &framebuffer)
        XCTAssertTrue(scene.isCommandPaletteOpen)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .fullScene)

        let escapeInvalidations = scene.handleHostEvent(
            .keyboard(
                LunaKeyboardEvent(
                    key: .escape,
                    modifiers: .none,
                    isRepeat: false
                )
            ),
            framebufferSize: initialSize
        )
        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: escapeInvalidations
        )
        scene.render(into: &framebuffer)
        XCTAssertFalse(scene.isCommandPaletteOpen)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .fullScene)

        let textInvalidations = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "X")),
            framebufferSize: initialSize
        )
        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: textInvalidations
        )
        scene.render(into: &framebuffer)
        XCTAssertEqual(scene.takeFrameRenderReport()?.path, .partialDamage)

        let resized = LunaSizeI(width: 1_020, height: 680)
        let resizeInvalidations = scene.handleHostEvent(
            .windowResized(resized),
            framebufferSize: resized
        )
        framebuffer = LunaFramebuffer(
            width: resized.width,
            height: resized.height
        )
        scene.updateHostRuntimeDiagnostics(
            timingStats: LunaFrameTimingStats(),
            inputStats: LunaInputCoalescingStats(),
            invalidations: resizeInvalidations
        )
        scene.render(into: &framebuffer)
        let resizeReport = try XCTUnwrap(scene.takeFrameRenderReport())
        XCTAssertEqual(resizeReport.path, .fullScene)
        XCTAssertEqual(resizeReport.invalidationClass, .resizeDriven)
    }

}
