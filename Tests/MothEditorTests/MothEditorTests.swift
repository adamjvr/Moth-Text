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
}
