// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaUI
@testable import MothApplication

final class MothUnicodeRenderingTests: XCTestCase {
    func testAccentedGlyphPaintsVisiblePixelsInsideItsEditorCell() throws {
        var scene = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 800, height: 500),
            initialText: "AéB"
        )
        var framebuffer = LunaFramebuffer(width: 800, height: 500)
        scene.render(into: &framebuffer)

        let textView = try XCTUnwrap(
            scene.paneTextView(for: MothApplicationShellScene.primaryPaneID)
        )
        let row = try XCTUnwrap(textView.layout().visibleLines.first)
        let glyphStartX = row.textBounds.x + row.rowGeometry.x(forUTF8Offset: 1)
        let glyphEndX = row.textBounds.x + row.rowGeometry.x(forUTF8Offset: 3)
        var colors = Set<[UInt8]>()
        for y in (row.rowBounds.y + 1)..<min(row.rowBounds.y + row.rowBounds.h - 1, framebuffer.height) {
            for x in glyphStartX..<min(max(glyphStartX + 1, glyphEndX), framebuffer.width) {
                colors.insert(pixel(in: framebuffer, x: x, y: y))
            }
        }

        XCTAssertGreaterThan(
            colors.count,
            1,
            "The accented character cell must contain foreground glyph pixels, not an advanced blank"
        )
    }

    func testDirtyIndicatorIsGeometryRatherThanAFontGlyph() {
        var scene = MothApplicationShellScene(
            initialSize: LunaSizeI(width: 800, height: 500),
            initialText: "base"
        )
        var clean = LunaFramebuffer(width: 800, height: 500)
        scene.render(into: &clean)

        _ = scene.handleHostEvent(
            .textInput(LunaTextInputEvent(text: "!")),
            framebufferSize: scene.framebufferSize
        )
        XCTAssertTrue(scene.documentSnapshot.isDirty)

        var dirty = LunaFramebuffer(width: 800, height: 500)
        scene.render(into: &dirty)

        let cleanMarker = markerPixels(in: clean)
        let dirtyMarker = markerPixels(in: dirty)
        XCTAssertNotEqual(cleanMarker, dirtyMarker)
        XCTAssertEqual(Set(dirtyMarker).count, 1, "The dirty marker should be one solid geometry color")
    }

    func testProductionMothTextPaintingDoesNotEmbedUnicodeBulletMarkers() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/MothApplication/MothApplicationShellScene.swift"),
            encoding: .utf8
        )
        let surface = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/MothApplication/MothPaneEditorSurface.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(shell.contains("•"))
        XCTAssertFalse(shell.contains("●"))
        XCTAssertTrue(shell.contains("MothUnicodeTextPainter.draw"))
        XCTAssertTrue(surface.contains("MothUnicodeTextPainter.draw"))
        XCTAssertFalse(surface.contains("LunaDebugBitmapTextRenderer.draw"))
    }

    func testInitializationFailureProducesPersistentVisibleDiagnosticsAndOneLog() {
        enum TestFailure: Error { case unavailable }
        var logMessages: [String] = []

        let state = MothUnicodeTextRendererState(
            rendererFactory: { _ in throw TestFailure.unavailable },
            logger: { logMessages.append($0) }
        )
        let diagnostics = state.diagnostics

        XCTAssertTrue(diagnostics.isUsingFallback)
        XCTAssertEqual(diagnostics.mode, .diagnosticFallback)
        XCTAssertEqual(diagnostics.warningMessage, "TEXT FALLBACK: Unicode renderer unavailable")
        XCTAssertEqual(
            diagnostics.prependingWarning(to: "UTF-8   SAVED"),
            "TEXT FALLBACK: Unicode renderer unavailable   UTF-8   SAVED"
        )
        XCTAssertTrue(diagnostics.failureDescription?.contains("unavailable") == true)
        XCTAssertEqual(logMessages.count, 1)
        XCTAssertTrue(logMessages[0].contains("diagnostic fallback active"))

        let geometry = state.geometry(
            for: LunaStaticTextGeometryRequest(sourceText: "fallback"),
            fallbackAdvance: LunaDebugBitmapTextRenderer.advance
        )
        XCTAssertEqual(
            geometry.x(forUTF8Offset: "fallback".utf8.count),
            "fallback".count * LunaDebugBitmapTextRenderer.advance
        )
    }

    private func markerPixels(in framebuffer: LunaFramebuffer) -> [[UInt8]] {
        var result: [[UInt8]] = []
        for y in 47..<52 {
            for x in 18..<23 {
                result.append(pixel(in: framebuffer, x: x, y: y))
            }
        }
        return result
    }

    private func pixel(in framebuffer: LunaFramebuffer, x: Int, y: Int) -> [UInt8] {
        var result: [UInt8] = []
        framebuffer.withUnsafePixelBytes { pointer, stride in
            let start = pointer.advanced(by: y * stride + x * 4)
            result = Array(UnsafeBufferPointer(start: start, count: 4))
        }
        return result
    }
}
