// SPDX-License-Identifier: MPL-2.0

import Foundation
import LunaCore
import LunaUI
import MothEditor
import MothTextCore

/// Read-only Luna adapter over an authoritative Moth source buffer.
///
/// The buffer remains owned and mutated by Moth. Luna receives immutable value
/// snapshots and never becomes the source of truth.
public struct MothLunaTextStorageAdapter: LunaTextStorageAdapter, Sendable {
    public let buffer: any MothSourceBuffer

    public init(buffer: any MothSourceBuffer) {
        self.buffer = buffer
    }

    public var documentID: LunaDocumentID {
        LunaDocumentID(rawValue: buffer.id.rawValue.uuidString)
    }

    public var contentRevision: LunaDocumentContentRevision {
        LunaDocumentContentRevision(rawValue: buffer.snapshot().revision.rawValue)
    }

    public func textSnapshot() -> LunaTextStorageSnapshot {
        let snapshot = buffer.snapshot()
        return LunaTextStorageSnapshot(
            documentID: documentID,
            revision: LunaDocumentContentRevision(rawValue: snapshot.revision.rawValue),
            text: snapshot.text
        )
    }
}

/// Converts Moth-owned view state into Luna's reusable presentation value.
public enum MothLunaViewProjection {
    public static func presentation(
        for view: MothEditorViewState,
        snapshot: LunaTextStorageSnapshot
    ) -> LunaDocumentViewPresentationState {
        let document = snapshot.staticDocument
        let caretLocation = document.location(forAbsoluteUTF8Offset: view.caret.rawValue)
        let selection: LunaStaticTextSelection?
        if let mothSelection = view.selection, !mothSelection.isCollapsed {
            selection = LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: document.location(
                        forAbsoluteUTF8Offset: mothSelection.anchor.rawValue
                    ),
                    focus: document.location(
                        forAbsoluteUTF8Offset: mothSelection.focus.rawValue
                    )
                )
            )
        } else {
            selection = nil
        }

        return LunaDocumentViewPresentationState(
            id: LunaDocumentViewID(rawValue: view.id.rawValue.uuidString),
            documentID: snapshot.documentID,
            caret: LunaStaticTextCaret(location: caretLocation),
            selection: selection,
            preferredUTF8Column: view.preferredUTF8Column,
            scrollState: LunaStaticTextScrollState(scrollTopLine: view.viewport.firstVisibleLine),
            observedRevision: view.observedRevision.map {
                LunaDocumentContentRevision(rawValue: $0.rawValue)
            }
        )
    }
}

/// Bridges Luna's reusable find panel to Moth's product-owned session policy.
public struct MothLunaFindPanelSession: LunaFindPanelSession, Sendable {
    public var mothSession: MothFindSession

    public init(buffer: any MothSourceBuffer) {
        self.mothSession = MothFindSession(buffer: buffer)
    }

    public func results(for query: LunaFindQuery) -> LunaFindResultSet {
        var scratch = MothFindSession(buffer: mothSession.buffer)
        let mothResults = scratch.update(query: Self.mothQuery(from: query))
        return Self.lunaResults(from: mothResults, buffer: mothSession.buffer)
    }

    public mutating func perform(
        action: LunaFindPanelAction,
        query: LunaFindQuery,
        selectedMatch: LunaFindMatch?,
        replacementText: String
    ) -> LunaFindSessionActionResult {
        _ = mothSession.update(query: Self.mothQuery(from: query))
        if let selectedMatch {
            mothSession.selectMatch(startingAtUTF8Offset: selectedMatch.utf8Offset)
        }

        let changed: Bool
        let replacementCount: Int
        switch action {
        case .findNext:
            mothSession.selectNext()
            changed = false
            replacementCount = 0
        case .findPrevious:
            mothSession.selectPrevious()
            changed = false
            replacementCount = 0
        case .replaceCurrent:
            let transaction = mothSession.replaceCurrent(with: replacementText)
            changed = transaction?.didChange ?? false
            replacementCount = changed ? 1 : 0
        case .replaceAll:
            replacementCount = mothSession.replaceAll(with: replacementText)
            changed = replacementCount > 0
        }

        return LunaFindSessionActionResult(
            results: Self.lunaResults(from: mothSession.results, buffer: mothSession.buffer),
            didChangeDocument: changed,
            replacementCount: replacementCount
        )
    }

    private static func mothQuery(from query: LunaFindQuery) -> MothFindQuery {
        MothFindQuery(
            text: query.text,
            options: MothFindOptions(
                isCaseSensitive: query.options.isCaseSensitive,
                matchesWholeWord: query.options.matchesWholeWord,
                usesRegularExpression: query.options.usesRegularExpression
            )
        )
    }

    private static func lunaResults(
        from results: MothFindResultSet,
        buffer: any MothSourceBuffer
    ) -> LunaFindResultSet {
        let snapshot = buffer.snapshot()
        let document = LunaStaticTextDocument(text: snapshot.text)
        let query = LunaFindQuery(
            text: results.query.text,
            options: LunaFindOptions(
                isCaseSensitive: results.query.options.isCaseSensitive,
                matchesWholeWord: results.query.options.matchesWholeWord,
                usesRegularExpression: results.query.options.usesRegularExpression
            )
        )
        let matches = results.matches.enumerated().map { index, match in
            LunaFindMatch(
                id: LunaNodeID(rawValue: "moth.find.match.\(index + 1)"),
                index: index,
                range: LunaTextRange(
                    anchor: document.location(forAbsoluteUTF8Offset: match.range.start.rawValue),
                    focus: document.location(forAbsoluteUTF8Offset: match.range.end.rawValue)
                ),
                matchedText: match.matchedText,
                utf8Offset: match.range.start.rawValue,
                utf8Length: match.range.length
            )
        }
        return LunaFindResultSet(
            query: query,
            matches: matches,
            selectedMatchIndex: results.selectedMatchIndex
        )
    }
}
