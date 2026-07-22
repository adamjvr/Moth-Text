// SPDX-License-Identifier: MPL-2.0

import Foundation
import MothTextCore

/// Direction-preserving selection owned by one editor view.
public struct MothTextSelection: Hashable, Sendable {
    public var anchor: MothTextOffset
    public var focus: MothTextOffset

    public init(anchor: MothTextOffset, focus: MothTextOffset) {
        self.anchor = anchor
        self.focus = focus
    }

    public var isCollapsed: Bool { anchor == focus }
    public var normalizedRange: MothTextRange { MothTextRange(start: anchor, end: focus) }
}

/// View-local viewport state. This does not belong to the shared source buffer.
public struct MothEditorViewportState: Hashable, Sendable {
    public var firstVisibleLine: Int

    /// Optional wrapped visual-row position. A nil value anchors layout to the
    /// logical firstVisibleLine, while a concrete value preserves continuation-
    /// row scrolling inside a long soft-wrapped logical line.
    public var firstVisibleVisualRow: Int?

    public var horizontalUTF8Column: Int

    public init(
        firstVisibleLine: Int = 0,
        firstVisibleVisualRow: Int? = nil,
        horizontalUTF8Column: Int = 0
    ) {
        self.firstVisibleLine = max(0, firstVisibleLine)
        self.firstVisibleVisualRow = firstVisibleVisualRow.map { max(0, $0) }
        self.horizontalUTF8Column = max(0, horizontalUTF8Column)
    }
}

/// Editor-domain composition state for one presentation of a source buffer.
///
/// Multiple values may reference one `bufferID`; caret, selection, preferred
/// column, and viewport remain independent by construction.
public struct MothEditorViewState: Hashable, Sendable {
    public var id: MothEditorViewID
    public var bufferID: MothBufferID
    public var caret: MothTextOffset
    public var selection: MothTextSelection?
    public var preferredUTF8Column: Int?
    public var viewport: MothEditorViewportState
    public private(set) var observedRevision: MothBufferRevision?

    public init(
        id: MothEditorViewID = MothEditorViewID(),
        bufferID: MothBufferID,
        caret: MothTextOffset = .zero,
        selection: MothTextSelection? = nil,
        preferredUTF8Column: Int? = nil,
        viewport: MothEditorViewportState = MothEditorViewportState(),
        firstVisibleLine: Int? = nil,
        observedRevision: MothBufferRevision? = nil
    ) {
        self.id = id
        self.bufferID = bufferID
        self.caret = caret
        self.selection = selection
        self.preferredUTF8Column = preferredUTF8Column.map { max(0, $0) }
        self.viewport = firstVisibleLine.map {
            MothEditorViewportState(
                firstVisibleLine: $0,
                firstVisibleVisualRow: viewport.firstVisibleVisualRow,
                horizontalUTF8Column: viewport.horizontalUTF8Column
            )
        } ?? viewport
        self.observedRevision = observedRevision
    }

    /// Compatibility accessor retained for the M0 workspace surface.
    public var firstVisibleLine: Int {
        get { viewport.firstVisibleLine }
        set { viewport.firstVisibleLine = max(0, newValue) }
    }

    /// Clamp only this view's coordinates to a new shared-buffer snapshot.
    /// Direction-preserving selections remain direction preserving.
    @discardableResult
    public mutating func synchronize(with snapshot: MothSourceBufferSnapshot) -> Bool {
        precondition(snapshot.id == bufferID, "Editor view cannot observe a different buffer")
        guard observedRevision != snapshot.revision else { return false }

        let upper = snapshot.utf8Count
        caret = MothGraphemeBoundary.atOrBefore(
            MothTextOffset(rawValue: min(caret.rawValue, upper)),
            in: snapshot.text
        )
        if let selection, !selection.isCollapsed {
            let anchor = MothGraphemeBoundary.atOrBefore(
                MothTextOffset(rawValue: min(selection.anchor.rawValue, upper)),
                in: snapshot.text
            )
            let focus = MothGraphemeBoundary.atOrBefore(
                MothTextOffset(rawValue: min(selection.focus.rawValue, upper)),
                in: snapshot.text
            )
            self.selection = anchor == focus
                ? nil
                : MothTextSelection(anchor: anchor, focus: focus)
        } else {
            selection = nil
        }

        viewport.firstVisibleLine = min(
            viewport.firstVisibleLine,
            max(0, lineCount(in: snapshot.text) - 1)
        )
        observedRevision = snapshot.revision
        return true
    }

    public mutating func setCaret(_ offset: MothTextOffset, extendingSelection: Bool = false) {
        if extendingSelection {
            let anchor = selection?.anchor ?? caret
            selection = MothTextSelection(anchor: anchor, focus: offset)
        } else {
            selection = nil
        }
        caret = offset
    }

    /// Apply a direction-preserving pointer or command selection and keep the
    /// caret at its focus edge. Collapsed ranges become ordinary caret state.
    public mutating func setSelection(anchor: MothTextOffset, focus: MothTextOffset) {
        caret = focus
        selection = anchor == focus ? nil : MothTextSelection(anchor: anchor, focus: focus)
    }

    /// Transform this view's coordinates through a known text transaction.
    /// Viewport ownership remains local and is intentionally not rewound.
    public mutating func transformCoordinates(through transaction: MothBufferTransaction) {
        precondition(transaction.bufferID == bufferID, "View and transaction buffers must match")
        caret = transaction.mapOffsetForward(caret)
        if let selection {
            let anchor = transaction.mapOffsetForward(selection.anchor)
            let focus = transaction.mapOffsetForward(selection.focus)
            self.selection = anchor == focus
                ? nil
                : MothTextSelection(anchor: anchor, focus: focus)
        }
    }

    private func lineCount(in text: String) -> Int {
        max(1, text.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        })
    }
}

public extension MothBufferTransaction {
    /// Map an absolute offset from the pre-transaction document into the
    /// post-transaction document. Positions at or inside the replaced range use
    /// after affinity so a caret at an insertion point follows inserted text.
    func mapOffsetForward(_ offset: MothTextOffset) -> MothTextOffset {
        let position = offset.rawValue
        let start = replacedRange.start.rawValue
        let oldEnd = replacedRange.end.rawValue
        let newEnd = start + insertedText.utf8.count

        if position < start { return offset }
        if position > oldEnd {
            return MothTextOffset(rawValue: position + newEnd - oldEnd)
        }
        return MothTextOffset(rawValue: newEnd)
    }
}

/// Legacy transaction helpers retained for low-level/headless callers.
/// Production document editing in C2 routes through `MothDocumentHistory`.
public enum MothEditorTransactions {
    @discardableResult
    public static func replaceSelection(
        in buffer: any MothSourceBuffer,
        view: inout MothEditorViewState,
        with replacement: String
    ) -> MothBufferTransaction {
        precondition(view.bufferID == buffer.id, "View and buffer identities must match")
        let range = view.selection?.normalizedRange ?? MothTextRange(start: view.caret, end: view.caret)
        let transaction = buffer.replace(range, with: replacement)
        view.caret = transaction.newCaret
        view.selection = nil
        view.preferredUTF8Column = nil
        _ = view.synchronize(with: buffer.snapshot())
        return transaction
    }

    @discardableResult
    public static func insert(
        _ text: String,
        in buffer: any MothSourceBuffer,
        view: inout MothEditorViewState
    ) -> MothBufferTransaction {
        replaceSelection(in: buffer, view: &view, with: text)
    }

    @discardableResult
    public static func deleteBackward(
        in buffer: any MothSourceBuffer,
        view: inout MothEditorViewState
    ) -> MothBufferTransaction {
        precondition(view.bufferID == buffer.id, "View and buffer identities must match")
        if let selection = view.selection, !selection.isCollapsed {
            return replaceSelection(in: buffer, view: &view, with: "")
        }

        let snapshot = buffer.snapshot()
        let caret = MothGraphemeBoundary.atOrBefore(view.caret, in: snapshot.text)
        let start = MothGraphemeBoundary.previous(before: caret, in: snapshot.text)
        let transaction = buffer.replace(MothTextRange(start: start, end: caret), with: "")
        view.caret = transaction.newCaret
        view.selection = nil
        view.preferredUTF8Column = nil
        _ = view.synchronize(with: buffer.snapshot())
        return transaction
    }

    @discardableResult
    public static func deleteForward(
        in buffer: any MothSourceBuffer,
        view: inout MothEditorViewState
    ) -> MothBufferTransaction {
        precondition(view.bufferID == buffer.id, "View and buffer identities must match")
        if let selection = view.selection, !selection.isCollapsed {
            return replaceSelection(in: buffer, view: &view, with: "")
        }

        let snapshot = buffer.snapshot()
        let caret = MothGraphemeBoundary.atOrBefore(view.caret, in: snapshot.text)
        let end = MothGraphemeBoundary.next(after: caret, in: snapshot.text)
        let transaction = buffer.replace(MothTextRange(start: caret, end: end), with: "")
        view.caret = transaction.newCaret
        view.selection = nil
        view.preferredUTF8Column = nil
        _ = view.synchronize(with: buffer.snapshot())
        return transaction
    }
}
