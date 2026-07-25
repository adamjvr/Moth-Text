// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaUI
@testable import MothApplication

final class MothC25BWrapIndexStoreTests: XCTestCase {
    private func makeIndex(width: Int) -> LunaStaticTextWrapIndex {
        LunaStaticTextWrapIndex(
            sourceUTF8Length: 8,
            viewportWidth: width,
            records: [
                LunaStaticTextWrapRecord(visualRowIndex: 0, utf8Range: 0..<4),
                LunaStaticTextWrapRecord(visualRowIndex: 1, utf8Range: 4..<8),
            ],
            diagnostics: LunaStaticTextWrapBuildDiagnostics(
                graphemeBoundaryCount: 9,
                widthProbeCount: 5,
                emittedRecordCount: 2
            )
        )
    }

    func testEqualRevisionLineAndWidthReuseIndex() {
        let store = MothDocumentWrapIndexStore()
        let presentation = MothDocumentPresentationKey(documentID: "a", revision: 3)
        let key = MothDocumentWrapIndexKey(
            presentationKey: presentation,
            lineIndex: 7,
            viewportWidth: 320
        )

        var buildCount = 0
        let first = store.index(for: key) {
            buildCount += 1
            return makeIndex(width: 320)
        }
        let second = store.index(for: key) {
            buildCount += 1
            return makeIndex(width: 320)
        }

        XCTAssertEqual(first, second)
        XCTAssertEqual(buildCount, 1)
        XCTAssertEqual(store.count, 1)
    }

    func testDifferentWidthsDoNotAlias() {
        let store = MothDocumentWrapIndexStore()
        let presentation = MothDocumentPresentationKey(documentID: "a", revision: 3)

        _ = store.insert(
            makeIndex(width: 240),
            for: MothDocumentWrapIndexKey(
                presentationKey: presentation,
                lineIndex: 0,
                viewportWidth: 240
            )
        )
        _ = store.insert(
            makeIndex(width: 480),
            for: MothDocumentWrapIndexKey(
                presentationKey: presentation,
                lineIndex: 0,
                viewportWidth: 480
            )
        )

        XCTAssertEqual(store.count, 2)
    }

    func testRevisionInvalidationPreservesOtherRevisions() {
        let store = MothDocumentWrapIndexStore()
        let old = MothDocumentPresentationKey(documentID: "a", revision: 1)
        let current = MothDocumentPresentationKey(documentID: "a", revision: 2)

        _ = store.insert(
            makeIndex(width: 300),
            for: MothDocumentWrapIndexKey(
                presentationKey: old,
                lineIndex: 0,
                viewportWidth: 300
            )
        )
        let currentKey = MothDocumentWrapIndexKey(
            presentationKey: current,
            lineIndex: 0,
            viewportWidth: 300
        )
        _ = store.insert(makeIndex(width: 300), for: currentKey)

        store.invalidate(presentationKey: old)

        XCTAssertEqual(store.count, 1)
        XCTAssertNotNil(store.index(for: currentKey))
    }
}
