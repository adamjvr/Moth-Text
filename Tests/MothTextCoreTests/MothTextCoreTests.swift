// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import MothTextCore

final class MothTextCoreTests: XCTestCase {
    func testBufferAndViewIdentityAreIndependent() {
        let buffer = MothBufferID()
        let first = MothEditorViewID()
        let second = MothEditorViewID()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(buffer, buffer)
    }
}
