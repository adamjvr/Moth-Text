// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import MothEditor
import MothTextCore

final class MothEditorTests: XCTestCase {
    func testTwoViewsCanReferenceOneBufferIndependently() {
        let buffer = MothBufferID()
        let first = MothEditorViewState(bufferID: buffer, firstVisibleLine: 4)
        let second = MothEditorViewState(bufferID: buffer, firstVisibleLine: 90)
        XCTAssertEqual(first.bufferID, second.bufferID)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.firstVisibleLine, second.firstVisibleLine)
    }

    func testEditThroughOneViewUpdatesSharedBufferButNotOtherViewPresentation() {
        let buffer = MothInMemorySourceBuffer(text: "alpha\nbeta\ngamma")
        var first = MothEditorViewState(
            bufferID: buffer.id,
            caret: MothTextOffset(rawValue: 5),
            preferredUTF8Column: 5,
            viewport: MothEditorViewportState(firstVisibleLine: 0)
        )
        var second = MothEditorViewState(
            bufferID: buffer.id,
            caret: MothTextOffset(rawValue: 11),
            preferredUTF8Column: 2,
            viewport: MothEditorViewportState(firstVisibleLine: 2)
        )
        _ = first.synchronize(with: buffer.snapshot())
        _ = second.synchronize(with: buffer.snapshot())

        let secondCaretBefore = second.caret
        let secondViewportBefore = second.viewport
        let secondPreferredBefore = second.preferredUTF8Column

        _ = MothEditorTransactions.insert("!", in: buffer, view: &first)
        let didObserve = second.synchronize(with: buffer.snapshot())

        XCTAssertEqual(buffer.snapshot().text, "alpha!\nbeta\ngamma")
        XCTAssertEqual(buffer.snapshot().revision, MothBufferRevision(rawValue: 1))
        XCTAssertEqual(first.caret, MothTextOffset(rawValue: 6))
        XCTAssertTrue(didObserve)
        XCTAssertEqual(second.caret, secondCaretBefore)
        XCTAssertEqual(second.viewport, secondViewportBefore)
        XCTAssertEqual(second.preferredUTF8Column, secondPreferredBefore)
    }

    func testSelectionReplacementUpdatesOnlyInitiatingView() {
        let buffer = MothInMemorySourceBuffer(text: "one two three")
        var view = MothEditorViewState(
            bufferID: buffer.id,
            caret: MothTextOffset(rawValue: 7),
            selection: MothTextSelection(anchor: MothTextOffset(rawValue: 4), focus: MothTextOffset(rawValue: 7))
        )
        _ = view.synchronize(with: buffer.snapshot())

        let transaction = MothEditorTransactions.replaceSelection(in: buffer, view: &view, with: "TWO")

        XCTAssertEqual(transaction.removedText, "two")
        XCTAssertEqual(buffer.snapshot().text, "one TWO three")
        XCTAssertEqual(view.caret, MothTextOffset(rawValue: 7))
        XCTAssertNil(view.selection)
    }

    func testDeleteBackwardAcrossMultibyteScalarLeavesCaretOnValidBoundary() {
        let buffer = MothInMemorySourceBuffer(text: "AéZ")
        var view = MothEditorViewState(
            bufferID: buffer.id,
            caret: MothTextOffset(rawValue: 3)
        )
        _ = view.synchronize(with: buffer.snapshot())

        let transaction = MothEditorTransactions.deleteBackward(in: buffer, view: &view)

        XCTAssertEqual(transaction.replacedRange, MothTextRange(start: 1, end: 3))
        XCTAssertEqual(transaction.removedText, "é")
        XCTAssertEqual(buffer.snapshot().text, "AZ")
        XCTAssertEqual(view.caret, MothTextOffset(rawValue: 1))
    }

    func testFindSessionOwnsReplacementPolicy() {
        let buffer = MothInMemorySourceBuffer(text: "cat dog cat")
        var session = MothFindSession(buffer: buffer)
        let results = session.update(query: MothFindQuery(text: "cat"))

        XCTAssertEqual(results.matches.count, 2)
        XCTAssertEqual(results.matches[0].range, MothTextRange(start: 0, end: 3))
        XCTAssertEqual(session.replaceAll(with: "fox"), 2)
        XCTAssertEqual(buffer.snapshot().text, "fox dog fox")
        XCTAssertTrue(buffer.snapshot().isDirty)
    }

    func testFindSessionRefreshesStaleResultsBeforeReplacement() {
        let buffer = MothInMemorySourceBuffer(text: "cat cat")
        var session = MothFindSession(buffer: buffer)
        _ = session.update(query: MothFindQuery(text: "cat"))
        _ = buffer.replace(MothTextRange(start: 0, end: 0), with: "big ")

        let transaction = session.replaceCurrent(with: "fox")

        XCTAssertEqual(transaction?.replacedRange, MothTextRange(start: 4, end: 7))
        XCTAssertEqual(buffer.snapshot().text, "big fox cat")
    }
}
