// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Immutable value snapshot of one authoritative Moth source buffer revision.
public struct MothSourceBufferSnapshot: Hashable, Sendable {
    public var id: MothBufferID
    public var revision: MothBufferRevision
    public var savedRevision: MothBufferRevision
    public var text: String

    public init(
        id: MothBufferID,
        revision: MothBufferRevision,
        savedRevision: MothBufferRevision,
        text: String
    ) {
        self.id = id
        self.revision = revision
        self.savedRevision = savedRevision
        self.text = text
    }

    public var utf8Count: Int { text.utf8.count }
    public var isDirty: Bool { revision != savedRevision }
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
        self.newCaret = newCaret
        self.didChange = didChange
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

    @discardableResult
    func replace(_ range: MothTextRange, with replacement: String) -> MothBufferTransaction

    func markSaved()
}
