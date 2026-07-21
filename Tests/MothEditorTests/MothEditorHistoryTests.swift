// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import MothEditor
import MothTextCore

final class MothEditorHistoryTests: XCTestCase {
    func testInsertUndoRedoKeepsRevisionMonotonic() throws {
        let buffer = MothInMemorySourceBuffer(text: "hello")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var primary = MothEditorViewState(bufferID: buffer.id, caret: 5)
        var others: [MothEditorViewState] = []
        _ = primary.synchronize(with: buffer.snapshot())

        let edit = try XCTUnwrap(history.insert(" world", in: buffer, originView: &primary, otherViews: &others))
        XCTAssertEqual(buffer.snapshot().text, "hello world")
        XCTAssertEqual(buffer.snapshot().revision.rawValue, 1)
        XCTAssertEqual(edit.displayName, "Insert Text")

        var views = [primary]
        let undo = try XCTUnwrap(history.undo(in: buffer, views: &views))
        XCTAssertEqual(buffer.snapshot().text, "hello")
        XCTAssertEqual(buffer.snapshot().revision.rawValue, 2)
        XCTAssertEqual(views[0].caret, 5)
        XCTAssertFalse(undo.canUndo)
        XCTAssertTrue(undo.canRedo)

        let redo = try XCTUnwrap(history.redo(in: buffer, views: &views))
        XCTAssertEqual(buffer.snapshot().text, "hello world")
        XCTAssertEqual(buffer.snapshot().revision.rawValue, 3)
        XCTAssertEqual(views[0].caret, 11)
        XCTAssertTrue(redo.canUndo)
        XCTAssertFalse(redo.canRedo)
    }

    func testUndoBackToOriginalSavedHistoryStateBecomesClean() throws {
        let buffer = MothInMemorySourceBuffer(text: "saved")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id, caret: 5)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        _ = history.insert("!", in: buffer, originView: &view, otherViews: &others)
        XCTAssertTrue(buffer.snapshot().isDirty)

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        let undone = buffer.snapshot()
        XCTAssertEqual(undone.text, "saved")
        XCTAssertFalse(undone.isDirty)
        XCTAssertNotEqual(undone.revision, undone.savedRevision)

        _ = history.redo(in: buffer, views: &views)
        XCTAssertTrue(buffer.snapshot().isDirty)
    }

    func testSaveCheckpointInMiddleOfHistoryIsCleanOnlyAtThatState() throws {
        let buffer = MothInMemorySourceBuffer(text: "")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        _ = history.insert("one", in: buffer, originView: &view, otherViews: &others)
        history.breakCoalescing()
        let saved = buffer.snapshot()
        buffer.markSaved(historyState: saved.historyState, revision: saved.revision)
        XCTAssertFalse(buffer.snapshot().isDirty)

        _ = history.insert(" two", in: buffer, originView: &view, otherViews: &others)
        XCTAssertTrue(buffer.snapshot().isDirty)

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "one")
        XCTAssertFalse(buffer.snapshot().isDirty)

        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "")
        XCTAssertTrue(buffer.snapshot().isDirty)

        _ = history.redo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "one")
        XCTAssertFalse(buffer.snapshot().isDirty)
    }

    func testOrdinaryTypingCoalescesDeterministically() throws {
        let buffer = MothInMemorySourceBuffer()
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        for character in ["h", "e", "l", "l", "o"] {
            _ = history.insert(character, in: buffer, originView: &view, otherViews: &others)
        }
        XCTAssertEqual(buffer.snapshot().text, "hello")
        XCTAssertEqual(history.status().undoGroupCount, 1)

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "")
        XCTAssertEqual(views[0].caret, .zero)
    }

    func testExplicitBoundarySeparatesTypingGroups() throws {
        let buffer = MothInMemorySourceBuffer()
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        _ = history.insert("hello", in: buffer, originView: &view, otherViews: &others)
        history.breakCoalescing()
        _ = history.insert(" world", in: buffer, originView: &view, otherViews: &others)
        XCTAssertEqual(history.status().undoGroupCount, 2)

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "hello")
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "")
    }

    func testNewlineAlwaysFormsDistinctGroup() throws {
        let buffer = MothInMemorySourceBuffer()
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        _ = history.insert("hello", in: buffer, originView: &view, otherViews: &others)
        _ = history.insert("\n", in: buffer, originView: &view, otherViews: &others)
        _ = history.insert("world", in: buffer, originView: &view, otherViews: &others)
        XCTAssertEqual(history.status().undoGroupCount, 3)

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "hello\n")
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "hello")
    }

    func testRepeatedBackspaceCoalescesAndRestoresUTF8Text() throws {
        let buffer = MothInMemorySourceBuffer(text: "AéBC")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id, caret: 5)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        _ = history.deleteBackward(in: buffer, originView: &view, otherViews: &others)
        _ = history.deleteBackward(in: buffer, originView: &view, otherViews: &others)
        _ = history.deleteBackward(in: buffer, originView: &view, otherViews: &others)
        XCTAssertEqual(buffer.snapshot().text, "A")
        XCTAssertEqual(history.status().undoGroupCount, 1)

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "AéBC")
        XCTAssertEqual(views[0].caret, 5)
    }

    func testDeleteDirectionChangeBreaksCoalescence() throws {
        let buffer = MothInMemorySourceBuffer(text: "abc")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id, caret: 1)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        _ = history.deleteForward(in: buffer, originView: &view, otherViews: &others)
        _ = history.deleteBackward(in: buffer, originView: &view, otherViews: &others)
        XCTAssertEqual(history.status().undoGroupCount, 2)
    }

    func testSelectionReplacementIsAtomicAndRestoresSelection() throws {
        let buffer = MothInMemorySourceBuffer(text: "one cat three")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(
            bufferID: buffer.id,
            caret: 7,
            selection: MothTextSelection(anchor: 4, focus: 7),
            preferredUTF8Column: 7
        )
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        _ = history.insert("dog", in: buffer, originView: &view, otherViews: &others)
        XCTAssertEqual(buffer.snapshot().text, "one dog three")
        XCTAssertNil(view.selection)

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "one cat three")
        XCTAssertEqual(views[0].selection, MothTextSelection(anchor: 4, focus: 7))
        XCTAssertEqual(views[0].preferredUTF8Column, 7)
    }

    func testNewEditAfterUndoInvalidatesRedoAndUsesFreshState() throws {
        let buffer = MothInMemorySourceBuffer()
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        _ = history.insert("a", in: buffer, originView: &view, otherViews: &others)
        history.breakCoalescing()
        _ = history.insert("b", in: buffer, originView: &view, otherViews: &others)
        let abandonedState = buffer.snapshot().historyState

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        view = views[0]
        XCTAssertTrue(history.status().canRedo)

        var noOthers: [MothEditorViewState] = []
        _ = history.insert("c", in: buffer, originView: &view, otherViews: &noOthers)
        XCTAssertFalse(history.status().canRedo)
        XCTAssertNotEqual(buffer.snapshot().historyState, abandonedState)
        XCTAssertGreaterThan(buffer.snapshot().historyState.rawValue, abandonedState.rawValue)
    }

    func testOtherPaneCoordinatesTransformAndReverseSelectionDirectionSurvives() throws {
        let buffer = MothInMemorySourceBuffer(text: "0123456789")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var primary = MothEditorViewState(bufferID: buffer.id, caret: 2)
        var secondary = MothEditorViewState(
            bufferID: buffer.id,
            caret: 8,
            selection: MothTextSelection(anchor: 8, focus: 6),
            viewport: MothEditorViewportState(firstVisibleLine: 4, firstVisibleVisualRow: 9)
        )
        _ = primary.synchronize(with: buffer.snapshot())
        _ = secondary.synchronize(with: buffer.snapshot())
        let secondaryViewport = secondary.viewport
        var others = [secondary]

        _ = history.insert("XX", in: buffer, originView: &primary, otherViews: &others)
        secondary = others[0]
        XCTAssertEqual(secondary.caret, 10)
        XCTAssertEqual(secondary.selection, MothTextSelection(anchor: 10, focus: 8))
        XCTAssertEqual(secondary.viewport, secondaryViewport)

        var views = [primary, secondary]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(views[0].caret, 2)
        XCTAssertEqual(views[1].caret, 8)
        XCTAssertEqual(views[1].selection, MothTextSelection(anchor: 8, focus: 6))
        XCTAssertEqual(views[1].viewport, secondaryViewport)
    }

    func testUndoFromDifferentActivePaneDoesNotTransferOriginState() throws {
        let buffer = MothInMemorySourceBuffer(text: "abc")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var primary = MothEditorViewState(bufferID: buffer.id, caret: 3)
        var secondary = MothEditorViewState(bufferID: buffer.id, caret: 1)
        _ = primary.synchronize(with: buffer.snapshot())
        _ = secondary.synchronize(with: buffer.snapshot())
        var others = [secondary]
        _ = history.insert("!", in: buffer, originView: &primary, otherViews: &others)

        var views = [primary, others[0]]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(views[0].caret, 3)
        XCTAssertEqual(views[1].caret, 1)
        XCTAssertNotEqual(views[0].caret, views[1].caret)
    }

    func testMissingOriginViewIsHandledSafely() throws {
        let buffer = MothInMemorySourceBuffer(text: "abc")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var origin = MothEditorViewState(bufferID: buffer.id, caret: 3)
        var survivor = MothEditorViewState(bufferID: buffer.id, caret: 1)
        _ = origin.synchronize(with: buffer.snapshot())
        _ = survivor.synchronize(with: buffer.snapshot())
        var others = [survivor]
        _ = history.insert("!", in: buffer, originView: &origin, otherViews: &others)

        var onlySurvivor = [others[0]]
        XCTAssertNotNil(history.undo(in: buffer, views: &onlySurvivor))
        XCTAssertEqual(buffer.snapshot().text, "abc")
        XCTAssertEqual(onlySurvivor[0].caret, 1)
    }

    func testReplaceAllBatchIsOneAtomicGroup() throws {
        let buffer = MothInMemorySourceBuffer(text: "cat dog cat")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id, caret: 0)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        let result = history.performBatchReplacements(
            [
                (MothTextRange(start: 8, end: 11), "fox"),
                (MothTextRange(start: 0, end: 3), "fox"),
            ],
            intent: .replaceAll,
            in: buffer,
            originView: &view,
            otherViews: &others
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(buffer.snapshot().text, "fox dog fox")
        XCTAssertEqual(history.status().undoGroupCount, 1)

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "cat dog cat")
        _ = history.redo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "fox dog fox")
    }

    func testNoOpDoesNotEnterHistoryOrInvalidateRedo() throws {
        let buffer = MothInMemorySourceBuffer(text: "same")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(
            bufferID: buffer.id,
            caret: 4,
            selection: MothTextSelection(anchor: 0, focus: 4)
        )
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        XCTAssertNil(history.insert("same", in: buffer, originView: &view, otherViews: &others))
        XCTAssertFalse(history.status().canUndo)
        XCTAssertEqual(buffer.snapshot().revision, .initial)
    }

    func testExternalPrimitiveMutationResetsRetainedHistory() throws {
        let buffer = MothInMemorySourceBuffer()
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())
        _ = history.insert("a", in: buffer, originView: &view, otherViews: &others)
        XCTAssertTrue(history.status().canUndo)

        _ = buffer.replace(MothTextRange(start: 1, end: 1), with: "external")
        history.breakCoalescing()
        var views = [view]
        XCTAssertNil(history.undo(in: buffer, views: &views))
        XCTAssertFalse(history.status().canUndo)
    }

    func testHistoryMemoryBudgetTrimsOldestGroups() throws {
        let buffer = MothInMemorySourceBuffer()
        let history = MothDocumentHistory(initialState: .initial, memoryBudgetBytes: 600)
        var view = MothEditorViewState(bufferID: buffer.id)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        for text in ["first", "second", "third"] {
            _ = history.insert(text, in: buffer, originView: &view, otherViews: &others)
            history.breakCoalescing()
        }
        XCTAssertLessThanOrEqual(history.status().retainedByteEstimate, 600)
        XCTAssertLessThan(history.status().undoGroupCount, 3)
    }
    func testFindSessionReplaceAllUsesOneHistoryGroup() throws {
        let buffer = MothInMemorySourceBuffer(text: "cat dog cat")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())
        var find = MothFindSession(buffer: buffer)
        _ = find.update(query: MothFindQuery(text: "cat"))

        XCTAssertNotNil(find.replaceAll(
            with: "fox",
            history: history,
            originView: &view,
            otherViews: &others
        ))
        XCTAssertEqual(buffer.snapshot().text, "fox dog fox")
        XCTAssertEqual(history.status().undoGroupCount, 1)

        var views = [view]
        _ = history.undo(in: buffer, views: &views)
        XCTAssertEqual(buffer.snapshot().text, "cat dog cat")
    }

    func testProductionApplicationAndWorkspaceDoNotBypassDocumentHistory() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let roots = [
            repositoryRoot.appendingPathComponent("Sources/MothApplication", isDirectory: true),
            repositoryRoot.appendingPathComponent("Sources/MothWorkspace", isDirectory: true),
        ]
        var violations: [String] = []
        for root in roots {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let source = try String(contentsOf: url, encoding: .utf8)
                if source.contains("buffer.replace(") {
                    violations.append(url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: ""))
                }
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "Production document/application mutations must pass through MothDocumentHistory: \(violations)"
        )
    }

    func testMultiEditReplayUsesTransientStatesUntilFinalPrimitive() throws {
        let buffer = MothInMemorySourceBuffer(text: "cat dog cat")
        let history = MothDocumentHistory(initialState: buffer.snapshot().historyState)
        var view = MothEditorViewState(bufferID: buffer.id)
        var others: [MothEditorViewState] = []
        _ = view.synchronize(with: buffer.snapshot())

        let edit = try XCTUnwrap(history.performBatchReplacements(
            [
                (MothTextRange(start: 8, end: 11), "elephant"),
                (MothTextRange(start: 0, end: 3), "a"),
            ],
            intent: .replaceAll,
            in: buffer,
            originView: &view,
            otherViews: &others
        ))
        let finalEditedState = buffer.snapshot().historyState
        XCTAssertEqual(edit.transactions.count, 2)

        var views = [view]
        let undo = try XCTUnwrap(history.undo(in: buffer, views: &views))
        XCTAssertEqual(undo.transactions.count, 2)
        XCTAssertNotEqual(undo.transactions[0].historyStateAfter, .initial)
        XCTAssertEqual(undo.transactions[1].historyStateAfter, .initial)
        XCTAssertEqual(buffer.snapshot().text, "cat dog cat")

        let redo = try XCTUnwrap(history.redo(in: buffer, views: &views))
        XCTAssertEqual(redo.transactions.count, 2)
        XCTAssertNotEqual(redo.transactions[0].historyStateAfter, finalEditedState)
        XCTAssertEqual(redo.transactions[1].historyStateAfter, finalEditedState)
        XCTAssertEqual(buffer.snapshot().text, "a dog elephant")
    }

}
