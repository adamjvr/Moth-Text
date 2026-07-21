// SPDX-License-Identifier: MPL-2.0

import Foundation

/// First production-shaped Moth source buffer.
///
/// This implementation uses a Swift String behind a lock for the M1 vertical
/// slice. The public protocol and typed UTF-8 coordinates are designed so a rope
/// or piece-table implementation can replace it later without changing editor
/// view ownership or Luna integration seams.
public final class MothInMemorySourceBuffer: MothSourceBuffer, @unchecked Sendable {
    public let id: MothBufferID

    private let lock = NSLock()
    private var textStorage: String
    private var revisionStorage: MothBufferRevision
    private var savedRevisionStorage: MothBufferRevision
    private var historyStateStorage: MothHistoryStateID
    private var savedHistoryStateStorage: MothHistoryStateID
    private var nextHistoryStateRawValue: UInt64

    public init(
        id: MothBufferID = MothBufferID(),
        text: String = "",
        revision: MothBufferRevision = .initial,
        savedRevision: MothBufferRevision? = nil,
        historyState: MothHistoryStateID? = nil,
        savedHistoryState: MothHistoryStateID? = nil
    ) {
        self.id = id
        self.textStorage = text
        self.revisionStorage = revision
        let resolvedSavedRevision = savedRevision ?? revision
        self.savedRevisionStorage = resolvedSavedRevision
        let resolvedHistoryState = historyState
            ?? MothHistoryStateID(rawValue: revision.rawValue)
        self.historyStateStorage = resolvedHistoryState
        self.savedHistoryStateStorage = savedHistoryState
            ?? MothHistoryStateID(rawValue: resolvedSavedRevision.rawValue)
        self.nextHistoryStateRawValue = max(
            resolvedHistoryState.rawValue,
            self.savedHistoryStateStorage.rawValue
        ) &+ 1
    }

    public func snapshot() -> MothSourceBufferSnapshot {
        lock.withLock {
            MothSourceBufferSnapshot(
                id: id,
                revision: revisionStorage,
                savedRevision: savedRevisionStorage,
                historyState: historyStateStorage,
                savedHistoryState: savedHistoryStateStorage,
                text: textStorage
            )
        }
    }

    @discardableResult
    public func replace(_ range: MothTextRange, with replacement: String) -> MothBufferTransaction {
        lock.withLock {
            let target = MothHistoryStateID(rawValue: nextHistoryStateRawValue)
            let transaction = applyReplacementLocked(
                range,
                with: replacement,
                resultingHistoryState: target
            )
            if transaction.didChange {
                nextHistoryStateRawValue &+= 1
            }
            return transaction
        }
    }

    @discardableResult
    public func applyHistoryReplacement(
        _ range: MothTextRange,
        with replacement: String,
        resultingHistoryState: MothHistoryStateID
    ) -> MothBufferTransaction {
        lock.withLock {
            applyReplacementLocked(
                range,
                with: replacement,
                resultingHistoryState: resultingHistoryState
            )
        }
    }

    public func markSaved() {
        lock.withLock {
            savedRevisionStorage = revisionStorage
            savedHistoryStateStorage = historyStateStorage
        }
    }

    public func markSaved(historyState: MothHistoryStateID, revision: MothBufferRevision) {
        lock.withLock {
            savedHistoryStateStorage = historyState
            savedRevisionStorage = revision
        }
    }

    private func applyReplacementLocked(
        _ range: MothTextRange,
        with replacement: String,
        resultingHistoryState: MothHistoryStateID
    ) -> MothBufferTransaction {
        let beforeRevision = revisionStorage
        let beforeHistoryState = historyStateStorage
        let requested = range
        let clamped = range.clamped(toUTF8Count: textStorage.utf8.count)
        let startIndex = stringIndex(forUTF8Offset: clamped.start.rawValue, bias: .backward)
        let endIndex = stringIndex(forUTF8Offset: clamped.end.rawValue, bias: .forward)
        let actualRange = MothTextRange(
            start: utf8Offset(of: startIndex),
            end: utf8Offset(of: endIndex)
        )
        let removed = String(textStorage[startIndex..<endIndex])
        let didChange = removed != replacement

        if didChange {
            textStorage.replaceSubrange(startIndex..<endIndex, with: replacement)
            revisionStorage = MothBufferRevision(rawValue: revisionStorage.rawValue &+ 1)
            historyStateStorage = resultingHistoryState
            nextHistoryStateRawValue = max(
                nextHistoryStateRawValue,
                resultingHistoryState.rawValue &+ 1
            )
        }

        let newCaret = MothTextOffset(
            rawValue: actualRange.start.rawValue + replacement.utf8.count
        )
        return MothBufferTransaction(
            bufferID: id,
            requestedRange: requested,
            replacedRange: actualRange,
            removedText: removed,
            insertedText: replacement,
            revisionBefore: beforeRevision,
            revisionAfter: revisionStorage,
            historyStateBefore: beforeHistoryState,
            historyStateAfter: didChange ? historyStateStorage : beforeHistoryState,
            newCaret: newCaret,
            didChange: didChange
        )
    }

    private func utf8Offset(of index: String.Index) -> Int {
        guard let utf8Index = index.samePosition(in: textStorage.utf8) else {
            return 0
        }
        return textStorage.utf8.distance(from: textStorage.utf8.startIndex, to: utf8Index)
    }

    private enum SnapBias { case backward, forward }

    private func stringIndex(forUTF8Offset offset: Int, bias: SnapBias) -> String.Index {
        let utf8Count = textStorage.utf8.count
        let clamped = min(max(0, offset), utf8Count)

        func exact(_ candidate: Int) -> String.Index? {
            let utf8Index = textStorage.utf8.index(textStorage.utf8.startIndex, offsetBy: candidate)
            return utf8Index.samePosition(in: textStorage)
        }

        if let index = exact(clamped) { return index }

        switch bias {
        case .backward:
            var candidate = clamped
            while candidate > 0 {
                candidate -= 1
                if let index = exact(candidate) { return index }
            }
            return textStorage.startIndex

        case .forward:
            var candidate = clamped
            while candidate < utf8Count {
                candidate += 1
                if let index = exact(candidate) { return index }
            }
            return textStorage.endIndex
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
