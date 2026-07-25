// SPDX-License-Identifier: MPL-2.0
import XCTest
import LunaUI
@testable import MothApplication

final class MothC25CVisualRowIndexStoreTests: XCTestCase {
    func testEqualGeometryKeysReuseIndex() {
        let store = MothDocumentVisualRowIndexStore()
        let presentation = MothDocumentPresentationKey(documentID: "a", revision: 9)
        let key = MothDocumentVisualRowIndexKey(presentationKey: presentation, viewportWidth: 640, wrapMode: .soft)
        var builds = 0
        let first = store.index(for: key) { builds += 1; return LunaStaticTextVisualRowIndex(visualRowCountsByLogicalLine: [1, 3]) }
        let second = store.index(for: key) { builds += 1; return LunaStaticTextVisualRowIndex(visualRowCountsByLogicalLine: [99]) }
        XCTAssertEqual(first, second)
        XCTAssertEqual(builds, 1)
    }

    func testDifferentWidthsAndModesDoNotAlias() {
        let store = MothDocumentVisualRowIndexStore()
        let presentation = MothDocumentPresentationKey(documentID: "a", revision: 9)
        for width in [420, 860] {
            _ = store.index(for: MothDocumentVisualRowIndexKey(presentationKey: presentation, viewportWidth: width, wrapMode: .soft)) {
                LunaStaticTextVisualRowIndex(visualRowCountsByLogicalLine: [1, 2])
            }
        }
        _ = store.index(for: MothDocumentVisualRowIndexKey(presentationKey: presentation, viewportWidth: 420, wrapMode: .none)) {
            LunaStaticTextVisualRowIndex(visualRowCountsByLogicalLine: [1, 1])
        }
        XCTAssertEqual(store.count, 3)
    }

    func testRevisionInvalidationPreservesCurrentRevision() {
        let store = MothDocumentVisualRowIndexStore()
        let stale = MothDocumentPresentationKey(documentID: "a", revision: 8)
        let current = MothDocumentPresentationKey(documentID: "a", revision: 9)
        let staleKey = MothDocumentVisualRowIndexKey(presentationKey: stale, viewportWidth: 600, wrapMode: .soft)
        let currentKey = MothDocumentVisualRowIndexKey(presentationKey: current, viewportWidth: 600, wrapMode: .soft)
        _ = store.index(for: staleKey) { LunaStaticTextVisualRowIndex(visualRowCountsByLogicalLine: [3]) }
        _ = store.index(for: currentKey) { LunaStaticTextVisualRowIndex(visualRowCountsByLogicalLine: [2]) }
        store.invalidate(presentationKey: stale)
        XCTAssertNil(store.index(for: staleKey))
        XCTAssertNotNil(store.index(for: currentKey))
    }
}
