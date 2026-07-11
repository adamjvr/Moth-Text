// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaUI
import MothEditor
import MothTextCore
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
            location: LunaPointI(x: 400, y: 120),
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

    func testCommittedTextInputMutatesMothBufferAndPreservesSecondaryViewState() {
        var scene = MothApplicationShellScene(initialText: "abc")
        let secondaryID = scene.secondaryView.id
        let secondaryPreferred = scene.secondaryView.preferredUTF8Column
        let secondaryViewport = scene.secondaryView.viewport

        let invalidations = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "X")),
            framebufferSize: LunaSizeI(width: 1100, height: 720)
        )

        XCTAssertEqual(scene.bufferSnapshot.text, "Xabc")
        XCTAssertEqual(scene.bufferSnapshot.revision, MothBufferRevision(rawValue: 1))
        XCTAssertEqual(scene.secondaryView.id, secondaryID)
        XCTAssertEqual(scene.secondaryView.preferredUTF8Column, secondaryPreferred)
        XCTAssertEqual(scene.secondaryView.viewport, secondaryViewport)
        XCTAssertTrue(invalidations.reasons.contains(.textInput))
    }

    func testLunaStorageAdapterProjectsImmutableMothSnapshot() {
        let buffer = MothInMemorySourceBuffer(text: "hello")
        let adapter = MothLunaTextStorageAdapter(buffer: buffer)
        let first = adapter.textSnapshot()
        _ = buffer.replace(MothTextRange(start: 5, end: 5), with: "!")
        let second = adapter.textSnapshot()

        XCTAssertEqual(first.text, "hello")
        XCTAssertEqual(first.revision, .initial)
        XCTAssertEqual(second.text, "hello!")
        XCTAssertEqual(second.revision, LunaDocumentContentRevision(rawValue: 1))
        XCTAssertEqual(first.documentID, second.documentID)
    }

    func testMothViewProjectsToIndependentLunaPresentationState() {
        let buffer = MothInMemorySourceBuffer(text: "one\ntwo")
        var first = MothEditorViewState(bufferID: buffer.id, caret: MothTextOffset(rawValue: 1), firstVisibleLine: 0)
        var second = MothEditorViewState(bufferID: buffer.id, caret: MothTextOffset(rawValue: 6), firstVisibleLine: 1)
        _ = first.synchronize(with: buffer.snapshot())
        _ = second.synchronize(with: buffer.snapshot())
        let snapshot = MothLunaTextStorageAdapter(buffer: buffer).textSnapshot()

        let firstProjection = MothLunaViewProjection.presentation(for: first, snapshot: snapshot)
        let secondProjection = MothLunaViewProjection.presentation(for: second, snapshot: snapshot)

        XCTAssertEqual(firstProjection.documentID, secondProjection.documentID)
        XCTAssertNotEqual(firstProjection.id, secondProjection.id)
        XCTAssertNotEqual(firstProjection.caret, secondProjection.caret)
        XCTAssertNotEqual(firstProjection.scrollState, secondProjection.scrollState)
    }

    func testMothFindSessionAdapterPerformsReplacementBehindLunaPanel() {
        let buffer = MothInMemorySourceBuffer(text: "cat dog cat")
        var adapter = MothLunaFindPanelSession(buffer: buffer)
        var panel = LunaFindPanelState(queryText: "cat", replaceText: "fox")
        panel.refreshResults(using: adapter)

        let result = panel.perform(.replaceAll, using: &adapter)

        XCTAssertTrue(result.didChangeDocument)
        XCTAssertEqual(result.replacementCount, 2)
        XCTAssertEqual(buffer.snapshot().text, "fox dog fox")
    }

    func testShellRendersDistinctChromeAndActualTextPixels() {
        var scene = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 800, height: 600),
            initialText: "MOTH"
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

        // The first glyph begins in the real editor text region at x ~= 259 on
        // an 800-pixel window. At least one pixel in its 5x7 cell must differ
        // from the editor background.
        var glyphPixels = Set<[UInt8]>()
        for y in 78..<88 {
            for x in 259..<270 {
                glyphPixels.insert(pixel(atX: x, y: y))
            }
        }
        XCTAssertGreaterThan(glyphPixels.count, 1)
    }
}
