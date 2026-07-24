// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import MothApplication

final class MothC25APresentationStoreTests: XCTestCase {
    func testTwoPanesReuseSameRevisionSnapshot() {
        let store = MothDocumentPresentationStore()
        let key = MothDocumentPresentationKey(documentID: "document-a", revision: 9)

        let leftPane = store.presentation(for: key, sourceText: "alpha\nbeta")
        let rightPane = store.presentation(for: key, sourceText: "alpha\nbeta")

        XCTAssertTrue(leftPane === rightPane)
        XCTAssertEqual(store.count, 1)
    }

    func testMinimapRequestDoesNotCreateSecondProjection() {
        let store = MothDocumentPresentationStore()
        let key = MothDocumentPresentationKey(documentID: "document-a", revision: 2)

        let editor = store.presentation(for: key, sourceText: "one\ntwo\nthree")
        let minimap = store.presentation(for: key, sourceText: "one\ntwo\nthree")

        XCTAssertTrue(editor === minimap)
        XCTAssertEqual(minimap.logicalLineCount, 3)
        XCTAssertEqual(store.count, 1)
    }

    func testNewRevisionCreatesNewImmutableSnapshot() {
        let store = MothDocumentPresentationStore()
        let oldKey = MothDocumentPresentationKey(documentID: "document-a", revision: 10)
        let newKey = MothDocumentPresentationKey(documentID: "document-a", revision: 11)

        let oldSnapshot = store.presentation(for: oldKey, sourceText: "before")
        let newSnapshot = store.presentation(for: newKey, sourceText: "after")

        XCTAssertFalse(oldSnapshot === newSnapshot)
        XCTAssertEqual(oldSnapshot.document.text, "before")
        XCTAssertEqual(newSnapshot.document.text, "after")
        XCTAssertEqual(store.count, 2)
    }

    func testInvalidatingDocumentRemovesAllItsRevisionsOnly() {
        let store = MothDocumentPresentationStore()

        _ = store.presentation(
            for: MothDocumentPresentationKey(documentID: "a", revision: 1),
            sourceText: "a1"
        )
        _ = store.presentation(
            for: MothDocumentPresentationKey(documentID: "a", revision: 2),
            sourceText: "a2"
        )
        let b = store.presentation(
            for: MothDocumentPresentationKey(documentID: "b", revision: 1),
            sourceText: "b1"
        )

        store.invalidate(documentID: "a")

        XCTAssertEqual(store.count, 1)
        XCTAssertTrue(
            store.cachedPresentation(
                for: MothDocumentPresentationKey(documentID: "b", revision: 1)
            ) === b
        )
    }

    func testSameRevisionKeyWithChangedTextReplacesStalePresentation() {
        let store = MothDocumentPresentationStore()
        let key = MothDocumentPresentationKey(documentID: "a", revision: 1)

        let first = store.presentation(for: key, sourceText: "first")
        let replacement = store.presentation(for: key, sourceText: "replacement")

        XCTAssertFalse(first === replacement)
        XCTAssertEqual(replacement.document.text, "replacement")
        XCTAssertEqual(store.count, 1)
    }
}
