// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import MothEditor
import MothTextCore

final class MothM22B2FindValidationTests: XCTestCase {
    func testInvalidRegularExpressionIsReportedWithoutMatches() {
        let buffer = MothInMemorySourceBuffer(text: "alpha beta")
        var session = MothFindSession(buffer: buffer)

        let result = session.update(
            query: MothFindQuery(
                text: "[",
                options: MothFindOptions(usesRegularExpression: true)
            )
        )

        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(buffer.snapshot().text, "alpha beta")
    }

    func testWholeWordUnicodeSearchUsesUTF8Ranges() {
        let buffer = MothInMemorySourceBuffer(text: "café caféine café")
        var session = MothFindSession(buffer: buffer)

        let result = session.update(
            query: MothFindQuery(
                text: "café",
                options: MothFindOptions(
                    isCaseSensitive: true,
                    matchesWholeWord: true
                )
            )
        )

        XCTAssertEqual(result.matches.count, 2)
        XCTAssertEqual(result.matches[0].range, MothTextRange(start: 0, end: 5))
        XCTAssertEqual(result.matches[1].matchedText, "café")
    }
}
