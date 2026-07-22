// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import MothEditor
import MothTextCore

final class MothGraphemeHistoryTests: XCTestCase {
    private let text = "Ae\u{301}Z"

    func testHistoryBackspaceRemovesOneExtendedGraphemeAndUndoRestoresIt() {
        let buffer = MothInMemorySourceBuffer(text: text)
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var origin = MothEditorViewState(
            bufferID: buffer.id,
            caret: MothTextOffset(rawValue: 4)
        )
        var others: [MothEditorViewState] = []
        _ = origin.synchronize(with: buffer.snapshot())

        let result = history.deleteBackward(
            in: buffer,
            originView: &origin,
            otherViews: &others
        )

        XCTAssertEqual(result?.transactions.first?.replacedRange, MothTextRange(start: 1, end: 4))
        XCTAssertEqual(buffer.snapshot().text, "AZ")
        XCTAssertEqual(origin.caret, MothTextOffset(rawValue: 1))

        var views = [origin]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, text)
        XCTAssertEqual(views[0].caret, MothTextOffset(rawValue: 4))
    }

    func testHistoryDeleteForwardRemovesOneExtendedGraphemeAndUndoRestoresIt() {
        let buffer = MothInMemorySourceBuffer(text: text)
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var origin = MothEditorViewState(
            bufferID: buffer.id,
            caret: MothTextOffset(rawValue: 1)
        )
        var others: [MothEditorViewState] = []
        _ = origin.synchronize(with: buffer.snapshot())

        let result = history.deleteForward(
            in: buffer,
            originView: &origin,
            otherViews: &others
        )

        XCTAssertEqual(result?.transactions.first?.replacedRange, MothTextRange(start: 1, end: 4))
        XCTAssertEqual(buffer.snapshot().text, "AZ")
        XCTAssertEqual(origin.caret, MothTextOffset(rawValue: 1))

        var views = [origin]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, text)
        XCTAssertEqual(views[0].caret, MothTextOffset(rawValue: 1))
    }
}
