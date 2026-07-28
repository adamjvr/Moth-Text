// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaCore
import LunaUI
import MothTextCore
@testable import MothApplication

final class MothC25FVirtualizedDocumentTests: XCTestCase {
    func testTwoPaneAndMinimapConsumersReuseOneRevisionProjection() {
        let buffer = MothInMemorySourceBuffer(text: "alpha\nbeta\ngamma")
        let snapshot = buffer.snapshot()
        let key = MothDocumentViewportPresentationKey(
            presentationKey: MothDocumentPresentationKey(
                documentID: "document-a",
                revision: snapshot.revision.rawValue
            )
        )
        let store = MothDocumentViewportPresentationStore()
        var builderCalls = 0

        let first = store.presentation(for: key) {
            builderCalls += 1
            return MothLunaTextStorageAdapter(buffer: buffer).textSnapshot()
        }
        let second = store.presentation(for: key) {
            builderCalls += 1
            return MothLunaTextStorageAdapter(buffer: buffer).textSnapshot()
        }

        XCTAssertTrue(first.presentation === second.presentation)
        XCTAssertTrue(first.virtualizationContext === second.virtualizationContext)
        XCTAssertEqual(builderCalls, 1)
        XCTAssertEqual(store.buildCount, 1)
        XCTAssertEqual(store.count, 1)
    }

    func testPresentationRetentionIsBoundedPerDocument() {
        let store = MothDocumentViewportPresentationStore(
            maximumRetainedRevisionsPerDocument: 2
        )

        for revision in 1...8 {
            let buffer = MothInMemorySourceBuffer(text: "revision \(revision)")
            let key = MothDocumentViewportPresentationKey(
                presentationKey: MothDocumentPresentationKey(
                    documentID: "document-a",
                    revision: UInt64(revision)
                )
            )
            _ = store.presentation(for: key) {
                MothLunaTextStorageAdapter(buffer: buffer).textSnapshot()
            }
        }

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.buildCount, 8)
    }

    func testFiftyThousandLineViewportShapesOnlyBoundedRows() {
        let text = (0..<50_000)
            .map { "line \($0) abcdefghijklmnopqrstuvwxyz" }
            .joined(separator: "\n")
        let buffer = MothInMemorySourceBuffer(text: text)
        let snapshot = buffer.snapshot()
        let store = MothDocumentViewportPresentationStore()
        let bundle = store.presentation(
            for: MothDocumentViewportPresentationKey(
                presentationKey: MothDocumentPresentationKey(
                    documentID: "large-document",
                    revision: snapshot.revision.rawValue
                )
            )
        ) {
            MothLunaTextStorageAdapter(buffer: buffer).textSnapshot()
        }
        let counter = C25FGeometryCounter()
        let viewport = bundle.virtualizationContext.viewport(
            requestedTopVisualRow: 25_000,
            maxVisibleVisualRowCount: 30,
            overscanVisualRowCount: 2,
            viewportWidth: 320,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: C25FCountingGeometryProvider(counter: counter)
        )

        XCTAssertEqual(viewport.visibleRows.count, 30)
        XCTAssertLessThan(counter.requestCount, 128)
        XCTAssertLessThan(bundle.virtualizationContext.cachedLineCount, 64)
    }

    func testMinimapSamplingIsBoundedByPixelHeightAndCoversDocumentExtent() {
        let plan = MothMinimapSamplePlan(
            logicalLineCount: 50_000,
            activeLogicalLineIndex: 25_000,
            availableHeight: 600,
            rowStride: 6
        )

        XCTAssertEqual(plan.samples.count, 100)
        XCTAssertEqual(plan.samples.first?.logicalLineIndex, 0)
        XCTAssertEqual(plan.samples.last?.logicalLineIndex, 49_999)
        XCTAssertEqual(plan.samples.filter(\.isActiveLineSample).count, 1)
    }
}

private final class C25FGeometryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0

    func record() { lock.withLock { requests += 1 } }
    var requestCount: Int { lock.withLock { requests } }
}

private struct C25FCountingGeometryProvider: LunaStaticTextGeometryProvider {
    let counter: C25FGeometryCounter

    func geometry(
        for request: LunaStaticTextGeometryRequest
    ) -> LunaStaticTextRowGeometry {
        counter.record()
        return LunaStaticTextRowGeometry.fixedAdvance(
            sourceText: request.sourceText,
            advance: 8
        )
    }
}
