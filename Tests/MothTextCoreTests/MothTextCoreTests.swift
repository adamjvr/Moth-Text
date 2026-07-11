// SPDX-License-Identifier: MPL-2.0

import Foundation
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

    func testInMemoryBufferOwnsRevisionAndDirtyState() {
        let buffer = MothInMemorySourceBuffer(text: "hello")
        XCTAssertEqual(buffer.snapshot().revision, .initial)
        XCTAssertFalse(buffer.snapshot().isDirty)

        let transaction = buffer.replace(MothTextRange(start: 5, end: 5), with: " world")

        XCTAssertTrue(transaction.didChange)
        XCTAssertEqual(transaction.revisionBefore, .initial)
        XCTAssertEqual(transaction.revisionAfter, MothBufferRevision(rawValue: 1))
        XCTAssertEqual(transaction.newCaret, MothTextOffset(rawValue: 11))
        XCTAssertEqual(buffer.snapshot().text, "hello world")
        XCTAssertTrue(buffer.snapshot().isDirty)

        buffer.markSaved()
        XCTAssertFalse(buffer.snapshot().isDirty)
    }

    func testNoOpReplacementDoesNotAdvanceRevision() {
        let buffer = MothInMemorySourceBuffer(text: "same")
        let transaction = buffer.replace(MothTextRange(start: 0, end: 4), with: "same")

        XCTAssertFalse(transaction.didChange)
        XCTAssertEqual(transaction.revisionBefore, transaction.revisionAfter)
        XCTAssertFalse(buffer.snapshot().isDirty)
    }

    func testUTF8RangesSnapSafelyAroundMultibyteScalars() {
        let buffer = MothInMemorySourceBuffer(text: "AéZ")
        XCTAssertEqual(buffer.snapshot().utf8Count, 4)
        XCTAssertEqual(buffer.snapshot().text(in: MothTextRange(start: 1, end: 3)), "é")

        let transaction = buffer.replace(MothTextRange(start: 2, end: 3), with: "E")
        XCTAssertEqual(transaction.removedText, "é")
        XCTAssertEqual(transaction.requestedRange, MothTextRange(start: 2, end: 3))
        XCTAssertEqual(transaction.replacedRange, MothTextRange(start: 1, end: 3))
        XCTAssertEqual(transaction.newCaret, MothTextOffset(rawValue: 2))
        XCTAssertEqual(buffer.snapshot().text, "AEZ")
    }

    func testMothTextCoreSourceDoesNotImportLuna() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appendingPathComponent("Sources/MothTextCore", isDirectory: true)
        let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        var violations: [String] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.range(of: #"(?m)^\s*(?:@_exported\s+)?import\s+Luna"#, options: .regularExpression) != nil {
                violations.append(url.lastPathComponent)
            }
        }

        XCTAssertTrue(violations.isEmpty, "MothTextCore must remain Luna-free: \(violations)")
    }
}
