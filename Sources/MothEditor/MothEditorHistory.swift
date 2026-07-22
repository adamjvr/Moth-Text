// SPDX-License-Identifier: MPL-2.0

import Foundation
import MothTextCore

/// User-meaningful category used for deterministic undo grouping.
public enum MothEditIntent: Hashable, Sendable {
    case typing
    case newline
    case deleteBackward
    case deleteForward
    case deleteSelection
    case replaceSelection
    case findReplace
    case replaceAll
    case command(String)

    public var displayName: String {
        switch self {
        case .typing: return "Insert Text"
        case .newline: return "Insert Newline"
        case .deleteBackward: return "Backspace"
        case .deleteForward: return "Delete Forward"
        case .deleteSelection: return "Delete Selection"
        case .replaceSelection: return "Replace Selection"
        case .findReplace: return "Replace Match"
        case .replaceAll: return "Replace All"
        case .command(let name): return name
        }
    }

    fileprivate var supportsCoalescing: Bool {
        switch self {
        case .typing, .deleteBackward, .deleteForward:
            return true
        default:
            return false
        }
    }
}

/// View-local editor meaning restored for the view that originated an edit.
/// Viewports are intentionally excluded: Undo changes document/editor state, not
/// the user's independent scroll positions.
public struct MothEditorViewCheckpoint: Hashable, Sendable {
    public var viewID: MothEditorViewID
    public var caret: MothTextOffset
    public var selection: MothTextSelection?
    public var preferredUTF8Column: Int?

    public init(view: MothEditorViewState) {
        self.viewID = view.id
        self.caret = view.caret
        self.selection = view.selection
        self.preferredUTF8Column = view.preferredUTF8Column
    }

    public func restore(into view: inout MothEditorViewState) {
        guard view.id == viewID else { return }
        view.caret = caret
        view.selection = selection
        view.preferredUTF8Column = preferredUTF8Column
    }
}

/// One primitive replacement retained inside a user-meaningful history group.
public struct MothHistoryEdit: Hashable, Sendable {
    public var replacedRange: MothTextRange
    public var removedText: String
    public var insertedText: String

    public init(transaction: MothBufferTransaction) {
        self.replacedRange = transaction.replacedRange
        self.removedText = transaction.removedText
        self.insertedText = transaction.insertedText
    }

    public var insertedRange: MothTextRange {
        MothTextRange(start: replacedRange.start, length: insertedText.utf8.count)
    }

    fileprivate var estimatedByteCost: Int {
        removedText.utf8.count + insertedText.utf8.count + 128
    }
}

public struct MothHistoryGroupID: Hashable, Sendable, Codable, RawRepresentable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// One atomic Undo/Redo unit. A group may contain many primitive replacements,
/// such as coalesced typing, repeated deletion, or Replace All.
public struct MothHistoryGroup: Hashable, Sendable {
    public var id: MothHistoryGroupID
    public var intent: MothEditIntent
    public var stateBefore: MothHistoryStateID
    public var stateAfter: MothHistoryStateID
    public var originBefore: MothEditorViewCheckpoint?
    public var originAfter: MothEditorViewCheckpoint?
    public var edits: [MothHistoryEdit]

    fileprivate var coalescingEpoch: UInt64

    public var displayName: String { intent.displayName }

    fileprivate var estimatedByteCost: Int {
        edits.reduce(256) { $0 + $1.estimatedByteCost }
    }
}

public enum MothHistoryActionKind: Hashable, Sendable {
    case edit
    case undo
    case redo
}

public struct MothHistoryActionResult: Hashable, Sendable {
    public var kind: MothHistoryActionKind
    public var groupID: MothHistoryGroupID
    public var displayName: String
    public var transactions: [MothBufferTransaction]
    public var canUndo: Bool
    public var canRedo: Bool

    public init(
        kind: MothHistoryActionKind,
        groupID: MothHistoryGroupID,
        displayName: String,
        transactions: [MothBufferTransaction],
        canUndo: Bool,
        canRedo: Bool
    ) {
        self.kind = kind
        self.groupID = groupID
        self.displayName = displayName
        self.transactions = transactions
        self.canUndo = canUndo
        self.canRedo = canRedo
    }
}

public struct MothHistoryStatus: Hashable, Sendable {
    public var canUndo: Bool
    public var canRedo: Bool
    public var undoGroupCount: Int
    public var redoGroupCount: Int
    public var currentState: MothHistoryStateID
    public var retainedByteEstimate: Int
}

/// Document-local Undo/Redo authority.
///
/// The history owns grouping and view restoration, while the source buffer owns
/// raw storage, UTF-8-safe primitive replacement, monotonic render revisions,
/// and the current/saved logical history-state identities.
public final class MothDocumentHistory: @unchecked Sendable {
    public static let defaultMemoryBudgetBytes = 96 * 1_024 * 1_024

    private let lock = NSLock()
    private var undoStack: [MothHistoryGroup] = []
    private var redoStack: [MothHistoryGroup] = []
    private var retainedByteEstimateStorage = 0
    private var coalescingEpoch: UInt64 = 0
    private var knownCurrentState: MothHistoryStateID

    public let memoryBudgetBytes: Int

    public init(
        initialState: MothHistoryStateID = .initial,
        memoryBudgetBytes: Int = MothDocumentHistory.defaultMemoryBudgetBytes
    ) {
        self.knownCurrentState = initialState
        self.memoryBudgetBytes = max(0, memoryBudgetBytes)
    }

    public func status() -> MothHistoryStatus {
        lock.withLock { statusLocked() }
    }

    /// Explicitly end the current deterministic typing/deletion run.
    public func breakCoalescing() {
        lock.withLock { coalescingEpoch &+= 1 }
    }

    /// Clear retained groups and adopt a new baseline, used after an external
    /// reload or another mutation source that intentionally replaces history.
    public func reset(to state: MothHistoryStateID) {
        lock.withLock { resetLocked(to: state) }
    }

    @discardableResult
    public func insert(
        _ text: String,
        in buffer: any MothSourceBuffer,
        originView: inout MothEditorViewState,
        otherViews: inout [MothEditorViewState]
    ) -> MothHistoryActionResult? {
        let intent: MothEditIntent
        if let selection = originView.selection, !selection.isCollapsed {
            intent = .replaceSelection
        } else if text.contains("\n") {
            intent = .newline
        } else {
            intent = .typing
        }
        let range = originView.selection?.normalizedRange
            ?? MothTextRange(start: originView.caret, end: originView.caret)
        return performReplacement(
            range,
            with: text,
            intent: intent,
            in: buffer,
            originView: &originView,
            otherViews: &otherViews,
            placesCaretAfterReplacement: true
        )
    }

    @discardableResult
    public func deleteBackward(
        in buffer: any MothSourceBuffer,
        originView: inout MothEditorViewState,
        otherViews: inout [MothEditorViewState]
    ) -> MothHistoryActionResult? {
        if let selection = originView.selection, !selection.isCollapsed {
            return performReplacement(
                selection.normalizedRange,
                with: "",
                intent: .deleteSelection,
                in: buffer,
                originView: &originView,
                otherViews: &otherViews,
                placesCaretAfterReplacement: true
            )
        }
        let snapshot = buffer.snapshot()
        let caret = MothGraphemeBoundary.atOrBefore(originView.caret, in: snapshot.text)
        let start = MothGraphemeBoundary.previous(before: caret, in: snapshot.text)
        return performReplacement(
            MothTextRange(start: start, end: caret),
            with: "",
            intent: .deleteBackward,
            in: buffer,
            originView: &originView,
            otherViews: &otherViews,
            placesCaretAfterReplacement: true
        )
    }

    @discardableResult
    public func deleteForward(
        in buffer: any MothSourceBuffer,
        originView: inout MothEditorViewState,
        otherViews: inout [MothEditorViewState]
    ) -> MothHistoryActionResult? {
        if let selection = originView.selection, !selection.isCollapsed {
            return performReplacement(
                selection.normalizedRange,
                with: "",
                intent: .deleteSelection,
                in: buffer,
                originView: &originView,
                otherViews: &otherViews,
                placesCaretAfterReplacement: true
            )
        }
        let snapshot = buffer.snapshot()
        let caret = MothGraphemeBoundary.atOrBefore(originView.caret, in: snapshot.text)
        let end = MothGraphemeBoundary.next(after: caret, in: snapshot.text)
        return performReplacement(
            MothTextRange(start: caret, end: end),
            with: "",
            intent: .deleteForward,
            in: buffer,
            originView: &originView,
            otherViews: &otherViews,
            placesCaretAfterReplacement: true
        )
    }

    @discardableResult
    public func performReplacement(
        _ range: MothTextRange,
        with replacement: String,
        intent: MothEditIntent,
        in buffer: any MothSourceBuffer,
        originView: inout MothEditorViewState,
        otherViews: inout [MothEditorViewState],
        placesCaretAfterReplacement: Bool = true
    ) -> MothHistoryActionResult? {
        lock.withLock {
            reconcileLocked(with: buffer.snapshot().historyState)
            precondition(originView.bufferID == buffer.id, "Origin view and buffer identities must match")
            precondition(otherViews.allSatisfy { $0.bufferID == buffer.id }, "All views must reference the edited buffer")

            let before = MothEditorViewCheckpoint(view: originView)
            let transaction = buffer.replace(range, with: replacement)
            guard transaction.didChange else { return nil }

            for index in otherViews.indices {
                otherViews[index].transformCoordinates(through: transaction)
            }
            if placesCaretAfterReplacement {
                originView.caret = transaction.newCaret
                originView.selection = nil
                originView.preferredUTF8Column = nil
            } else {
                originView.transformCoordinates(through: transaction)
            }

            let snapshot = buffer.snapshot()
            _ = originView.synchronize(with: snapshot)
            for index in otherViews.indices {
                _ = otherViews[index].synchronize(with: snapshot)
            }
            let after = MothEditorViewCheckpoint(view: originView)

            let group = recordLocked(
                edits: [MothHistoryEdit(transaction: transaction)],
                intent: intent,
                stateBefore: transaction.historyStateBefore,
                stateAfter: transaction.historyStateAfter,
                originBefore: before,
                originAfter: after
            )
            return resultLocked(kind: .edit, group: group, transactions: [transaction])
        }
    }

    /// Perform an ordered batch as one atomic history group. Callers normally
    /// provide ranges from the end of the document toward the beginning.
    @discardableResult
    public func performBatchReplacements(
        _ replacements: [(range: MothTextRange, replacement: String)],
        intent: MothEditIntent,
        in buffer: any MothSourceBuffer,
        originView: inout MothEditorViewState,
        otherViews: inout [MothEditorViewState]
    ) -> MothHistoryActionResult? {
        lock.withLock {
            reconcileLocked(with: buffer.snapshot().historyState)
            guard !replacements.isEmpty else { return nil }
            precondition(originView.bufferID == buffer.id, "Origin view and buffer identities must match")
            precondition(otherViews.allSatisfy { $0.bufferID == buffer.id }, "All views must reference the edited buffer")

            let before = MothEditorViewCheckpoint(view: originView)
            var transactions: [MothBufferTransaction] = []
            for replacement in replacements {
                let transaction = buffer.replace(replacement.range, with: replacement.replacement)
                guard transaction.didChange else { continue }
                originView.transformCoordinates(through: transaction)
                for index in otherViews.indices {
                    otherViews[index].transformCoordinates(through: transaction)
                }
                transactions.append(transaction)
            }
            guard let first = transactions.first, let last = transactions.last else { return nil }

            let snapshot = buffer.snapshot()
            _ = originView.synchronize(with: snapshot)
            for index in otherViews.indices {
                _ = otherViews[index].synchronize(with: snapshot)
            }
            let after = MothEditorViewCheckpoint(view: originView)
            let group = recordLocked(
                edits: transactions.map(MothHistoryEdit.init(transaction:)),
                intent: intent,
                stateBefore: first.historyStateBefore,
                stateAfter: last.historyStateAfter,
                originBefore: before,
                originAfter: after
            )
            return resultLocked(kind: .edit, group: group, transactions: transactions)
        }
    }

    @discardableResult
    public func undo(
        in buffer: any MothSourceBuffer,
        views: inout [MothEditorViewState]
    ) -> MothHistoryActionResult? {
        lock.withLock {
            reconcileLocked(with: buffer.snapshot().historyState)
            guard let group = undoStack.popLast() else { return nil }
            retainedByteEstimateStorage -= group.estimatedByteCost

            var transactions: [MothBufferTransaction] = []
            let inverseEdits = Array(group.edits.reversed())
            for (index, edit) in inverseEdits.enumerated() {
                // Intermediate primitives receive fresh transient state IDs so
                // a concurrent snapshot can never mistake partially replayed
                // group content for the final saved history state.
                let isFinalPrimitive = index == inverseEdits.count - 1
                let transaction = isFinalPrimitive
                    ? buffer.applyHistoryReplacement(
                        edit.insertedRange,
                        with: edit.removedText,
                        resultingHistoryState: group.stateBefore
                    )
                    : buffer.replace(edit.insertedRange, with: edit.removedText)
                precondition(transaction.didChange, "Recorded inverse edit must change the buffer")
                for index in views.indices {
                    views[index].transformCoordinates(through: transaction)
                }
                transactions.append(transaction)
            }
            restore(group.originBefore, in: &views)
            synchronize(&views, with: buffer.snapshot())

            redoStack.append(group)
            retainedByteEstimateStorage += group.estimatedByteCost
            knownCurrentState = group.stateBefore
            coalescingEpoch &+= 1
            return resultLocked(kind: .undo, group: group, transactions: transactions)
        }
    }

    @discardableResult
    public func redo(
        in buffer: any MothSourceBuffer,
        views: inout [MothEditorViewState]
    ) -> MothHistoryActionResult? {
        lock.withLock {
            reconcileLocked(with: buffer.snapshot().historyState)
            guard let group = redoStack.popLast() else { return nil }
            retainedByteEstimateStorage -= group.estimatedByteCost

            var transactions: [MothBufferTransaction] = []
            for (index, edit) in group.edits.enumerated() {
                // As with Undo, only the final primitive receives the retained
                // logical state. Earlier primitives stay on fresh transient
                // states and therefore remain unambiguously dirty.
                let isFinalPrimitive = index == group.edits.count - 1
                let transaction = isFinalPrimitive
                    ? buffer.applyHistoryReplacement(
                        edit.replacedRange,
                        with: edit.insertedText,
                        resultingHistoryState: group.stateAfter
                    )
                    : buffer.replace(edit.replacedRange, with: edit.insertedText)
                precondition(transaction.didChange, "Recorded forward edit must change the buffer")
                for index in views.indices {
                    views[index].transformCoordinates(through: transaction)
                }
                transactions.append(transaction)
            }
            restore(group.originAfter, in: &views)
            synchronize(&views, with: buffer.snapshot())

            undoStack.append(group)
            retainedByteEstimateStorage += group.estimatedByteCost
            knownCurrentState = group.stateAfter
            coalescingEpoch &+= 1
            trimUndoLocked()
            return resultLocked(kind: .redo, group: group, transactions: transactions)
        }
    }

    private func recordLocked(
        edits: [MothHistoryEdit],
        intent: MothEditIntent,
        stateBefore: MothHistoryStateID,
        stateAfter: MothHistoryStateID,
        originBefore: MothEditorViewCheckpoint?,
        originAfter: MothEditorViewCheckpoint?
    ) -> MothHistoryGroup {
        clearRedoLocked()
        let candidate = MothHistoryGroup(
            id: MothHistoryGroupID(),
            intent: intent,
            stateBefore: stateBefore,
            stateAfter: stateAfter,
            originBefore: originBefore,
            originAfter: originAfter,
            edits: edits,
            coalescingEpoch: coalescingEpoch
        )

        let recorded: MothHistoryGroup
        if var previous = undoStack.last,
           canCoalesce(previous: previous, next: candidate) {
            retainedByteEstimateStorage -= previous.estimatedByteCost
            previous.stateAfter = candidate.stateAfter
            previous.originAfter = candidate.originAfter
            previous.edits.append(contentsOf: candidate.edits)
            undoStack[undoStack.count - 1] = previous
            retainedByteEstimateStorage += previous.estimatedByteCost
            recorded = previous
        } else {
            undoStack.append(candidate)
            retainedByteEstimateStorage += candidate.estimatedByteCost
            recorded = candidate
        }

        knownCurrentState = stateAfter
        if !intent.supportsCoalescing { coalescingEpoch &+= 1 }
        trimUndoLocked()
        return recorded
    }

    private func canCoalesce(previous: MothHistoryGroup, next: MothHistoryGroup) -> Bool {
        guard previous.intent == next.intent,
              previous.intent.supportsCoalescing,
              previous.coalescingEpoch == next.coalescingEpoch,
              previous.originAfter?.viewID == next.originBefore?.viewID,
              previous.stateAfter == next.stateBefore,
              let last = previous.edits.last,
              let first = next.edits.first
        else { return false }

        switch previous.intent {
        case .typing:
            return last.removedText.isEmpty
                && first.removedText.isEmpty
                && first.replacedRange.start == last.insertedRange.end
        case .deleteBackward:
            return last.insertedText.isEmpty
                && first.insertedText.isEmpty
                && first.replacedRange.end == last.replacedRange.start
        case .deleteForward:
            return last.insertedText.isEmpty
                && first.insertedText.isEmpty
                && first.replacedRange.start == last.replacedRange.start
        default:
            return false
        }
    }

    private func reconcileLocked(with actualState: MothHistoryStateID) {
        if actualState != knownCurrentState {
            resetLocked(to: actualState)
        }
    }

    private func resetLocked(to state: MothHistoryStateID) {
        undoStack.removeAll(keepingCapacity: false)
        redoStack.removeAll(keepingCapacity: false)
        retainedByteEstimateStorage = 0
        knownCurrentState = state
        coalescingEpoch &+= 1
    }

    private func clearRedoLocked() {
        retainedByteEstimateStorage -= redoStack.reduce(0) { $0 + $1.estimatedByteCost }
        redoStack.removeAll(keepingCapacity: true)
    }

    private func trimUndoLocked() {
        while retainedByteEstimateStorage > memoryBudgetBytes, !undoStack.isEmpty {
            retainedByteEstimateStorage -= undoStack.removeFirst().estimatedByteCost
        }
        retainedByteEstimateStorage = max(0, retainedByteEstimateStorage)
    }

    private func restore(
        _ checkpoint: MothEditorViewCheckpoint?,
        in views: inout [MothEditorViewState]
    ) {
        guard let checkpoint,
              let index = views.firstIndex(where: { $0.id == checkpoint.viewID })
        else { return }
        checkpoint.restore(into: &views[index])
    }

    private func synchronize(
        _ views: inout [MothEditorViewState],
        with snapshot: MothSourceBufferSnapshot
    ) {
        for index in views.indices {
            _ = views[index].synchronize(with: snapshot)
        }
    }

    private func statusLocked() -> MothHistoryStatus {
        MothHistoryStatus(
            canUndo: !undoStack.isEmpty,
            canRedo: !redoStack.isEmpty,
            undoGroupCount: undoStack.count,
            redoGroupCount: redoStack.count,
            currentState: knownCurrentState,
            retainedByteEstimate: max(0, retainedByteEstimateStorage)
        )
    }

    private func resultLocked(
        kind: MothHistoryActionKind,
        group: MothHistoryGroup,
        transactions: [MothBufferTransaction]
    ) -> MothHistoryActionResult {
        MothHistoryActionResult(
            kind: kind,
            groupID: group.id,
            displayName: group.displayName,
            transactions: transactions,
            canUndo: !undoStack.isEmpty,
            canRedo: !redoStack.isEmpty
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
