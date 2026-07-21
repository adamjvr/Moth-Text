// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Stable logical position in one buffer's undo/redo history.
///
/// Unlike `MothBufferRevision`, this value is allowed to move backward during
/// Undo and forward during Redo. New branch edits always receive a fresh,
/// monotonically allocated identity so abandoned history states are never
/// accidentally reused.
public struct MothHistoryStateID: Hashable, Sendable, Codable, Comparable, RawRepresentable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let initial = MothHistoryStateID(rawValue: 0)

    public static func < (lhs: MothHistoryStateID, rhs: MothHistoryStateID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Immutable value snapshot of one authoritative Moth source-buffer revision.
public struct MothSourceBufferSnapshot: Hashable, Sendable {
    public var id: MothBufferID

    /// Monotonic content generation used to invalidate rendering, search
    /// results, and view projections. It never moves backward, including when
    /// history moves through Undo or Redo.
    public var revision: MothBufferRevision

    /// Revision whose bytes were most recently written. This remains useful for
    /// diagnostics, but dirty state is intentionally based on history identity.
    public var savedRevision: MothBufferRevision

    /// Current logical undo/redo position.
    public var historyState: MothHistoryStateID

    /// Logical state whose bytes were most recently written to disk.
    public var savedHistoryState: MothHistoryStateID
    public var text: String

    public init(
        id: MothBufferID,
        revision: MothBufferRevision,
        savedRevision: MothBufferRevision,
        historyState: MothHistoryStateID? = nil,
        savedHistoryState: MothHistoryStateID? = nil,
        text: String
    ) {
        self.id = id
        self.revision = revision
        self.savedRevision = savedRevision
        let currentState = historyState ?? MothHistoryStateID(rawValue: revision.rawValue)
        self.historyState = currentState
        self.savedHistoryState = savedHistoryState
            ?? MothHistoryStateID(rawValue: savedRevision.rawValue)
        self.text = text
    }

    public var utf8Count: Int { text.utf8.count }
    public var isDirty: Bool { historyState != savedHistoryState }
    public var fullRange: MothTextRange { MothTextRange(start: 0, end: utf8Count) }

    public func text(in range: MothTextRange) -> String {
        let clamped = range.clamped(toUTF8Count: utf8Count)
        let startIndex = stringIndex(forUTF8Offset: clamped.start.rawValue, bias: .backward)
        let endIndex = stringIndex(forUTF8Offset: clamped.end.rawValue, bias: .forward)
        return String(text[startIndex..<endIndex])
    }

    private enum SnapBias { case backward, forward }

    private func stringIndex(forUTF8Offset offset: Int, bias: SnapBias) -> String.Index {
        let clamped = min(max(0, offset), utf8Count)

        func exact(_ candidate: Int) -> String.Index? {
            let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: candidate)
            return utf8Index.samePosition(in: text)
        }

        if let index = exact(clamped) { return index }

        switch bias {
        case .backward:
            var candidate = clamped
            while candidate > 0 {
                candidate -= 1
                if let index = exact(candidate) { return index }
            }
            return text.startIndex

        case .forward:
            var candidate = clamped
            while candidate < utf8Count {
                candidate += 1
                if let index = exact(candidate) { return index }
            }
            return text.endIndex
        }
    }
}

/// Result of one authoritative Moth text transaction.
public struct MothBufferTransaction: Hashable, Sendable {
    public var bufferID: MothBufferID
    public var requestedRange: MothTextRange
    public var replacedRange: MothTextRange
    public var removedText: String
    public var insertedText: String
    public var revisionBefore: MothBufferRevision
    public var revisionAfter: MothBufferRevision
    public var historyStateBefore: MothHistoryStateID
    public var historyStateAfter: MothHistoryStateID
    public var newCaret: MothTextOffset
    public var didChange: Bool

    public init(
        bufferID: MothBufferID,
        requestedRange: MothTextRange,
        replacedRange: MothTextRange,
        removedText: String,
        insertedText: String,
        revisionBefore: MothBufferRevision,
        revisionAfter: MothBufferRevision,
        historyStateBefore: MothHistoryStateID = .initial,
        historyStateAfter: MothHistoryStateID = .initial,
        newCaret: MothTextOffset,
        didChange: Bool
    ) {
        self.bufferID = bufferID
        self.requestedRange = requestedRange
        self.replacedRange = replacedRange
        self.removedText = removedText
        self.insertedText = insertedText
        self.revisionBefore = revisionBefore
        self.revisionAfter = revisionAfter
        self.historyStateBefore = historyStateBefore
        self.historyStateAfter = historyStateAfter
        self.newCaret = newCaret
        self.didChange = didChange
    }

    /// Range occupied by inserted text in the post-transaction document.
    public var insertedRange: MothTextRange {
        MothTextRange(start: replacedRange.start, length: insertedText.utf8.count)
    }
}

/// Product-owned source-buffer contract.
///
/// The class constraint intentionally models shared authoritative storage: two
/// editor views retain the same buffer object while keeping independent view
/// state values. No Luna type appears in this target.
public protocol MothSourceBuffer: AnyObject, Sendable {
    var id: MothBufferID { get }
    func snapshot() -> MothSourceBufferSnapshot

    /// Apply a new branch edit and allocate a fresh logical history state.
    @discardableResult
    func replace(_ range: MothTextRange, with replacement: String) -> MothBufferTransaction

    /// Replay a previously recorded edit while moving to an existing logical
    /// history state. This is the primitive used by MothEditor undo/redo policy.
    @discardableResult
    func applyHistoryReplacement(
        _ range: MothTextRange,
        with replacement: String,
        resultingHistoryState: MothHistoryStateID
    ) -> MothBufferTransaction

    /// Mark the current state as saved.
    func markSaved()

    /// Mark the exact captured state/revision written by a potentially slow
    /// save operation. Newer concurrent edits therefore remain dirty.
    func markSaved(historyState: MothHistoryStateID, revision: MothBufferRevision)
}
