// SPDX-License-Identifier: MPL-2.0

import Foundation
import MothTextCore

public struct MothFindOptions: Hashable, Sendable {
    public var isCaseSensitive: Bool
    public var matchesWholeWord: Bool
    public var usesRegularExpression: Bool

    public init(
        isCaseSensitive: Bool = false,
        matchesWholeWord: Bool = false,
        usesRegularExpression: Bool = false
    ) {
        self.isCaseSensitive = isCaseSensitive
        self.matchesWholeWord = matchesWholeWord
        self.usesRegularExpression = usesRegularExpression
    }
}

public struct MothFindQuery: Hashable, Sendable {
    public var text: String
    public var options: MothFindOptions

    public init(text: String = "", options: MothFindOptions = MothFindOptions()) {
        self.text = text
        self.options = options
    }

    public var isEmpty: Bool { text.isEmpty }
}

public struct MothFindMatch: Hashable, Sendable {
    public var range: MothTextRange
    public var matchedText: String

    public init(range: MothTextRange, matchedText: String) {
        self.range = range
        self.matchedText = matchedText
    }
}

public struct MothFindResultSet: Hashable, Sendable {
    public var query: MothFindQuery
    public var bufferRevision: MothBufferRevision
    public var matches: [MothFindMatch]
    public var selectedMatchIndex: Int?

    public init(
        query: MothFindQuery,
        bufferRevision: MothBufferRevision,
        matches: [MothFindMatch],
        selectedMatchIndex: Int? = nil
    ) {
        self.query = query
        self.bufferRevision = bufferRevision
        self.matches = matches
        if let selectedMatchIndex, matches.indices.contains(selectedMatchIndex) {
            self.selectedMatchIndex = selectedMatchIndex
        } else {
            self.selectedMatchIndex = matches.isEmpty ? nil : 0
        }
    }

    public var selectedMatch: MothFindMatch? {
        guard let selectedMatchIndex, matches.indices.contains(selectedMatchIndex) else { return nil }
        return matches[selectedMatchIndex]
    }
}

/// Moth-owned search and replacement policy.
///
/// Luna may present the panel, but Moth performs scanning against an
/// authoritative buffer and groups replacement mutations on the product side.
public struct MothFindSession: Sendable {
    public let buffer: any MothSourceBuffer
    public private(set) var results: MothFindResultSet

    public init(buffer: any MothSourceBuffer) {
        self.buffer = buffer
        let snapshot = buffer.snapshot()
        self.results = MothFindResultSet(
            query: MothFindQuery(),
            bufferRevision: snapshot.revision,
            matches: []
        )
    }

    @discardableResult
    public mutating func update(query: MothFindQuery) -> MothFindResultSet {
        let snapshot = buffer.snapshot()
        let matches = Self.scan(snapshot: snapshot, query: query)
        results = MothFindResultSet(
            query: query,
            bufferRevision: snapshot.revision,
            matches: matches
        )
        return results
    }

    public mutating func selectNext() {
        guard !results.matches.isEmpty else { return }
        let next = (results.selectedMatchIndex ?? -1) + 1
        results.selectedMatchIndex = next < results.matches.count ? next : 0
    }

    public mutating func selectPrevious() {
        guard !results.matches.isEmpty else { return }
        let previous = (results.selectedMatchIndex ?? results.matches.count) - 1
        results.selectedMatchIndex = previous >= 0 ? previous : results.matches.count - 1
    }

    public mutating func selectMatch(startingAtUTF8Offset offset: Int) {
        guard let index = results.matches.firstIndex(where: { $0.range.start.rawValue == max(0, offset) }) else {
            return
        }
        results.selectedMatchIndex = index
    }

    @discardableResult
    public mutating func replaceCurrent(with replacement: String) -> MothBufferTransaction? {
        refreshIfStale()
        guard let match = results.selectedMatch else { return nil }
        let transaction = buffer.replace(match.range, with: replacement)
        _ = update(query: results.query)
        if !results.matches.isEmpty { selectNext() }
        return transaction
    }

    @discardableResult
    public mutating func replaceAll(with replacement: String) -> Int {
        refreshIfStale()
        let matches = results.matches
        guard !matches.isEmpty else { return 0 }
        for match in matches.reversed() {
            _ = buffer.replace(match.range, with: replacement)
        }
        _ = update(query: results.query)
        return matches.count
    }


    /// History-aware single replacement used by production document editing.
    /// The legacy overload above remains for low-level callers and compatibility
    /// tests, but application code should supply its document history and views.
    @discardableResult
    public mutating func replaceCurrent(
        with replacement: String,
        history: MothDocumentHistory,
        originView: inout MothEditorViewState,
        otherViews: inout [MothEditorViewState]
    ) -> MothHistoryActionResult? {
        refreshIfStale()
        guard let match = results.selectedMatch else { return nil }
        let result = history.performReplacement(
            match.range,
            with: replacement,
            intent: .findReplace,
            in: buffer,
            originView: &originView,
            otherViews: &otherViews,
            placesCaretAfterReplacement: true
        )
        _ = update(query: results.query)
        if !results.matches.isEmpty { selectNext() }
        return result
    }

    /// History-aware Replace All. Every primitive replacement is retained in one
    /// atomic group so one Undo restores the complete pre-command document.
    @discardableResult
    public mutating func replaceAll(
        with replacement: String,
        history: MothDocumentHistory,
        originView: inout MothEditorViewState,
        otherViews: inout [MothEditorViewState]
    ) -> MothHistoryActionResult? {
        refreshIfStale()
        let matches = results.matches
        guard !matches.isEmpty else { return nil }
        let result = history.performBatchReplacements(
            matches.reversed().map { (range: $0.range, replacement: replacement) },
            intent: .replaceAll,
            in: buffer,
            originView: &originView,
            otherViews: &otherViews
        )
        _ = update(query: results.query)
        return result
    }

    private mutating func refreshIfStale() {
        if buffer.snapshot().revision != results.bufferRevision {
            _ = update(query: results.query)
        }
    }

    private static func scan(snapshot: MothSourceBufferSnapshot, query: MothFindQuery) -> [MothFindMatch] {
        guard !query.isEmpty else { return [] }
        return query.options.usesRegularExpression
            ? regexMatches(in: snapshot.text, query: query)
            : literalMatches(in: snapshot.text, query: query)
    }

    private static func literalMatches(in text: String, query: MothFindQuery) -> [MothFindMatch] {
        let options: String.CompareOptions = query.options.isCaseSensitive ? [] : [.caseInsensitive]
        var searchStart = text.startIndex
        var matches: [MothFindMatch] = []

        while searchStart <= text.endIndex,
              let range = text.range(of: query.text, options: options, range: searchStart..<text.endIndex) {
            if !range.isEmpty, acceptsWordBoundary(in: text, range: range, wholeWord: query.options.matchesWholeWord) {
                matches.append(makeMatch(in: text, range: range))
            }
            guard !range.isEmpty else { break }
            searchStart = range.upperBound
        }
        return matches
    }

    private static func regexMatches(in text: String, query: MothFindQuery) -> [MothFindMatch] {
        let options: NSRegularExpression.Options = query.options.isCaseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: query.text, options: options) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var matches: [MothFindMatch] = []
        regex.enumerateMatches(in: text, range: fullRange) { result, _, _ in
            guard let result, result.range.length > 0, let range = Range(result.range, in: text) else { return }
            guard acceptsWordBoundary(in: text, range: range, wholeWord: query.options.matchesWholeWord) else { return }
            matches.append(makeMatch(in: text, range: range))
        }
        return matches
    }

    private static func makeMatch(in text: String, range: Range<String.Index>) -> MothFindMatch {
        let start = utf8Offset(of: range.lowerBound, in: text)
        let end = utf8Offset(of: range.upperBound, in: text)
        return MothFindMatch(
            range: MothTextRange(start: start, end: end),
            matchedText: String(text[range])
        )
    }

    private static func utf8Offset(of index: String.Index, in text: String) -> Int {
        guard let utf8Index = index.samePosition(in: text.utf8) else { return 0 }
        return text.utf8.distance(from: text.utf8.startIndex, to: utf8Index)
    }

    private static func acceptsWordBoundary(
        in text: String,
        range: Range<String.Index>,
        wholeWord: Bool
    ) -> Bool {
        guard wholeWord else { return true }
        let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
        let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        return !isWordCharacter(before) && !isWordCharacter(after)
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        if character == "_" { return true }
        return character.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
    }
}
