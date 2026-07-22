// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
@testable import MothApplication

final class MothInputLatencyTests: XCTestCase {
    func testLargeCommittedTextBatchAppliesAsOneDocumentTransaction() {
        var shell = MothApplicationShellScene(initialText: "")
        let text = String(repeating: "a", count: 1_000)

        let invalidations = shell.handleHostEvent(
            .textInput(LunaTextInputEvent(text: text)),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )

        XCTAssertTrue(invalidations.reasons.contains(.textInput))
        XCTAssertEqual(shell.bufferSnapshot.text, text)
        XCTAssertEqual(shell.primaryView.caret.rawValue, text.utf8.count)
        XCTAssertEqual(shell.historyStatus.undoGroupCount, 1)

        let undo = shell.undoDocument()
        XCTAssertNotNil(undo)
        XCTAssertEqual(shell.bufferSnapshot.text, "")
    }

    func testHostLatencyAndInputBatchDiagnosticsAreRetainedByShell() {
        var shell = MothApplicationShellScene(initialText: "")
        var timing = LunaFrameTimingStats(smoothingFactor: 1)
        timing.record(
            LunaFrameTimingSample(
                frameIndex: 1,
                startedAtNanoseconds: 1,
                inputNanoseconds: 1_000_000,
                renderNanoseconds: 2_000_000,
                presentNanoseconds: 1_000_000,
                inputToPresentNanoseconds: 5_000_000,
                totalNanoseconds: 3_000_000,
                invalidations: LunaFrameInvalidationSet(.textInput)
            )
        )
        let input = LunaInputCoalescingStats(
            receivedEventCount: 12,
            emittedEventCount: 2,
            receivedTextInputEventCount: 10,
            emittedTextInputEventCount: 1,
            receivedTextInputUTF8ByteCount: 10
        )

        shell.updateHostRuntimeDiagnostics(timingStats: timing, inputStats: input)

        XCTAssertEqual(shell.hostFrameTimingStats.movingAverageInputToPresentMilliseconds, 5, accuracy: 0.001)
        XCTAssertEqual(shell.hostInputStats.mergedTextInputEventCount, 9)
    }

    func testRepeatedRenderUsesBoundedShapedLayoutCache() throws {
        MothUnicodeTextPainter.resetPerformanceCountersForTesting()
        var shell = MothApplicationShellScene(
            initialText: (1...180).map { "line \($0): the quick brown fox jumps over the lazy dog" }.joined(separator: "\n")
        )
        var framebuffer = LunaFramebuffer(width: 1100, height: 720)

        shell.render(into: &framebuffer)
        let first = shell.unicodeTextPerformance
        shell.render(into: &framebuffer)
        let second = shell.unicodeTextPerformance

        if shell.unicodeTextDiagnostics.isUsingFallback {
            throw XCTSkip("Unicode renderer unavailable in this test environment")
        }

        XCTAssertGreaterThan(first.layoutRequestCount, 0)
        XCTAssertGreaterThan(second.layoutCacheHitCount, first.layoutCacheHitCount)

        // Exercise eviction with more unique mutable-line states than the cache
        // may retain. This models a long active line changing over many frames
        // without requiring the cache to preserve every historical prefix.
        for index in 0..<180 {
            _ = MothUnicodeTextPainter.geometry(
                for: "rapid-prefix-\(index)-" + String(repeating: "x", count: index % 37)
            )
        }
        let afterEviction = shell.unicodeTextPerformance
        XCTAssertLessThanOrEqual(afterEviction.layoutCacheEntryCount, 128)
        XCTAssertLessThanOrEqual(afterEviction.layoutCacheCost, 2 * 1024 * 1024)
    }

    func testCoalescedTextAndNavigationRemainOrdered() {
        let batch = LunaHostInputCoalescer().coalesce([
            .textInput(LunaTextInputEvent(text: "abc")),
            .textInput(LunaTextInputEvent(text: "def")),
            .keyboard(LunaKeyboardEvent(key: .arrowLeft)),
            .textInput(LunaTextInputEvent(text: "X")),
        ])
        var shell = MothApplicationShellScene(initialText: "")

        for event in batch.events {
            _ = shell.handleHostEvent(
                event,
                framebufferSize: LunaSizeI(width: 1100, height: 720)
            )
        }

        XCTAssertEqual(shell.bufferSnapshot.text, "abcdeXf")
        XCTAssertEqual(shell.primaryView.caret.rawValue, 6)
        XCTAssertEqual(batch.stats.mergedTextInputEventCount, 1)
    }
}
