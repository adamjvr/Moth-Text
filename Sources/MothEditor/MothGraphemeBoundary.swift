// SPDX-License-Identifier: MPL-2.0
//
// UTF-8 document-coordinate helpers for current String-backed editor snapshots.
// Moth retains byte-stable offsets while user-facing movement and deletion step
// across Swift extended grapheme clusters rather than individual UTF-8 bytes.

import Foundation
import MothTextCore

public enum MothHorizontalCaretDirection: Hashable, Sendable {
    case backward
    case forward
}

public enum MothGraphemeBoundary {
    public static func atOrBefore(
        _ offset: MothTextOffset,
        in text: String
    ) -> MothTextOffset {
        let target = clampedRawOffset(offset, in: text)
        var start = 0

        for character in text {
            let end = start + String(character).utf8.count
            if target < end {
                return MothTextOffset(rawValue: start)
            }
            if target == end {
                return MothTextOffset(rawValue: end)
            }
            start = end
        }

        return MothTextOffset(rawValue: text.utf8.count)
    }

    public static func atOrAfter(
        _ offset: MothTextOffset,
        in text: String
    ) -> MothTextOffset {
        let target = clampedRawOffset(offset, in: text)
        if target == 0 { return .zero }

        var start = 0
        for character in text {
            let end = start + String(character).utf8.count
            if target <= start {
                return MothTextOffset(rawValue: start)
            }
            if target <= end {
                return MothTextOffset(rawValue: end)
            }
            start = end
        }

        return MothTextOffset(rawValue: text.utf8.count)
    }

    public static func previous(
        before offset: MothTextOffset,
        in text: String
    ) -> MothTextOffset {
        let target = clampedRawOffset(offset, in: text)
        guard target > 0 else { return .zero }

        var start = 0
        for character in text {
            let end = start + String(character).utf8.count
            if target <= end {
                return MothTextOffset(rawValue: start)
            }
            start = end
        }

        return MothTextOffset(rawValue: start)
    }

    public static func next(
        after offset: MothTextOffset,
        in text: String
    ) -> MothTextOffset {
        let target = clampedRawOffset(offset, in: text)
        let upper = text.utf8.count
        guard target < upper else { return MothTextOffset(rawValue: upper) }

        var start = 0
        for character in text {
            let end = start + String(character).utf8.count
            if target < end {
                return MothTextOffset(rawValue: end)
            }
            start = end
        }

        return MothTextOffset(rawValue: upper)
    }

    private static func clampedRawOffset(
        _ offset: MothTextOffset,
        in text: String
    ) -> Int {
        min(max(0, offset.rawValue), text.utf8.count)
    }
}

public extension MothEditorViewState {
    mutating func moveCaretHorizontally(
        _ direction: MothHorizontalCaretDirection,
        in text: String,
        extendingSelection: Bool = false
    ) {
        if !extendingSelection, let selection, !selection.isCollapsed {
            let target = direction == .backward
                ? selection.normalizedRange.start
                : selection.normalizedRange.end
            setCaret(target)
            preferredUTF8Column = nil
            return
        }

        let target: MothTextOffset
        switch direction {
        case .backward:
            target = MothGraphemeBoundary.previous(before: caret, in: text)
        case .forward:
            target = MothGraphemeBoundary.next(after: caret, in: text)
        }

        setCaret(target, extendingSelection: extendingSelection)
        preferredUTF8Column = nil
    }
}
