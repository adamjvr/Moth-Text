// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
@testable import MothWorkspace
import MothEditor
import MothTextCore

final class MothWorkspaceTests: XCTestCase {
    func testWorkspaceOwnsActiveViewPolicy() {
        let document = MothFileDocument(untitledText: "hello")
        let view = MothEditorViewState(bufferID: document.buffer.id)
        let workspace = MothWorkspaceState(
            documents: [document],
            editorViews: [view],
            documentIDByViewID: [view.id: document.id],
            activeDocumentID: document.id,
            activeViewID: view.id
        )

        XCTAssertEqual(workspace.activeViewID, view.id)
        XCTAssertEqual(workspace.activeDocumentID, document.id)
        XCTAssertTrue(workspace.activeDocument === document)
    }

    func testOpenCreatesCleanFileBackedDocument() throws {
        let fixture = try TemporaryTextFile(contents: "alpha\nbeta")
        let controller = MothDocumentController(fileAccess: MothLocalDocumentFileAccess())

        let document = try controller.open(url: fixture.url)
        let snapshot = document.snapshot()

        XCTAssertEqual(snapshot.fileURL, fixture.url.standardizedFileURL)
        XCTAssertEqual(snapshot.displayName, fixture.url.lastPathComponent)
        XCTAssertEqual(snapshot.encoding, .utf8)
        XCTAssertEqual(snapshot.buffer.text, "alpha\nbeta")
        XCTAssertFalse(snapshot.isDirty)
        XCTAssertNotNil(snapshot.knownFileState)
    }

    func testUTF8BOMIsDetectedAndPreservedWhenSaving() throws {
        let fixture = try TemporaryTextFile(data: Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8))
        let controller = MothDocumentController(fileAccess: MothLocalDocumentFileAccess())
        let document = try controller.open(url: fixture.url)

        XCTAssertEqual(document.snapshot().encoding, .utf8WithByteOrderMark)
        _ = document.buffer.replace(MothTextRange(start: 5, end: 5), with: "!")
        let saved = try controller.save(document)
        let data = try Data(contentsOf: fixture.url)

        XCTAssertTrue(data.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertEqual(String(data: data.dropFirst(3), encoding: .utf8), "hello!")
        XCTAssertFalse(saved.isDirty)
    }

    func testSaveAsAssignsIdentityAndClearsDirtyState() throws {
        let directory = try TemporaryDirectory()
        let destination = directory.url.appendingPathComponent("saved.txt")
        let document = MothFileDocument(untitledText: "draft", displayName: "untitled.txt")
        _ = document.buffer.replace(MothTextRange(start: 5, end: 5), with: "!")
        XCTAssertTrue(document.snapshot().isDirty)

        let controller = MothDocumentController(fileAccess: MothLocalDocumentFileAccess())
        let saved = try controller.saveAs(document, to: destination)

        XCTAssertEqual(saved.fileURL, destination.standardizedFileURL)
        XCTAssertEqual(saved.displayName, "saved.txt")
        XCTAssertFalse(saved.isDirty)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "draft!")
    }

    func testExternalChangeDetectionComparesKnownDiskState() throws {
        let fixture = try TemporaryTextFile(contents: "before")
        let controller = MothDocumentController(fileAccess: MothLocalDocumentFileAccess())
        let document = try controller.open(url: fixture.url)

        XCTAssertFalse(try controller.hasExternalChange(document))
        try Data("after with a different size".utf8).write(to: fixture.url, options: .atomic)
        XCTAssertTrue(try controller.hasExternalChange(document))
    }


    func testSaveAsRefusesUnconfirmedOverwrite() throws {
        let directory = try TemporaryDirectory()
        let destination = directory.url.appendingPathComponent("existing.txt")
        try Data("keep me".utf8).write(to: destination)
        let document = MothFileDocument(untitledText: "replacement")
        let controller = MothDocumentController(fileAccess: MothLocalDocumentFileAccess())

        XCTAssertThrowsError(try controller.saveAs(document, to: destination)) { error in
            XCTAssertEqual(error as? MothDocumentFileError, .destinationExists(destination.path))
        }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "keep me")
        XCTAssertTrue(document.snapshot().isUntitled)
    }

    func testTwoWorkspaceViewsMapToOneFileDocumentWithoutSharingPresentation() {
        let document = MothFileDocument(untitledText: "one\ntwo\nthree")
        let first = MothEditorViewState(bufferID: document.buffer.id, caret: .zero, firstVisibleLine: 0)
        let second = MothEditorViewState(
            bufferID: document.buffer.id,
            caret: MothTextOffset(rawValue: 7),
            firstVisibleLine: 2
        )
        let workspace = MothWorkspaceState(
            documents: [document],
            editorViews: [first, second],
            documentIDByViewID: [first.id: document.id, second.id: document.id],
            activeDocumentID: document.id,
            activeViewID: first.id
        )

        XCTAssertEqual(workspace.documentID(for: first.id), document.id)
        XCTAssertEqual(workspace.documentID(for: second.id), document.id)
        XCTAssertNotEqual(first.caret, second.caret)
        XCTAssertNotEqual(first.viewport, second.viewport)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MothWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class TemporaryTextFile {
    private let directory: TemporaryDirectory
    let url: URL

    convenience init(contents: String) throws {
        try self.init(data: Data(contents.utf8))
    }

    init(data: Data) throws {
        directory = try TemporaryDirectory()
        url = directory.url.appendingPathComponent("fixture.txt")
        try data.write(to: url)
    }
}
