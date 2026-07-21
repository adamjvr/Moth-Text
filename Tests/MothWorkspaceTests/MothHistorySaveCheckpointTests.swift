// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
@testable import MothWorkspace
import MothEditor
import MothTextCore

final class MothHistorySaveCheckpointTests: XCTestCase {
    func testDocumentSavePreservesUndoHistoryAndMovesCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MothC2Save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("history.txt")

        let document = MothFileDocument(untitledText: "base")
        var view = MothEditorViewState(bufferID: document.buffer.id, caret: 4)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: document.buffer.snapshot())
        _ = document.history.insert(" saved", in: document.buffer, originView: &view, otherViews: &others)

        let controller = MothDocumentController(fileAccess: MothLocalDocumentFileAccess())
        _ = try controller.saveAs(document, to: destination)
        XCTAssertFalse(document.snapshot().isDirty)
        XCTAssertTrue(document.history.status().canUndo)

        var views = [view]
        _ = document.history.undo(in: document.buffer, views: &views)
        XCTAssertEqual(document.snapshot().buffer.text, "base")
        XCTAssertTrue(document.snapshot().isDirty)

        _ = document.history.redo(in: document.buffer, views: &views)
        XCTAssertEqual(document.snapshot().buffer.text, "base saved")
        XCTAssertFalse(document.snapshot().isDirty)
    }

    func testMarkingCapturedSaveStateDoesNotCleanNewerEdit() throws {
        let buffer = MothInMemorySourceBuffer(text: "base")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id, caret: 4)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        _ = history.insert(" one", in: buffer, originView: &view, otherViews: &others)
        let captured = buffer.snapshot()
        history.breakCoalescing()
        _ = history.insert(" two", in: buffer, originView: &view, otherViews: &others)

        buffer.markSaved(historyState: captured.historyState, revision: captured.revision)
        XCTAssertEqual(buffer.snapshot().text, "base one two")
        XCTAssertTrue(buffer.snapshot().isDirty)
    }
}
