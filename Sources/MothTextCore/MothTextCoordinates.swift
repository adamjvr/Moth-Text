// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Absolute UTF-8 byte offset in a Moth source buffer.
public struct MothTextOffset: Hashable, Sendable, Codable, Comparable, RawRepresentable, ExpressibleByIntegerLiteral {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = max(0, rawValue)
    }

    public init(integerLiteral value: Int) {
        self.init(rawValue: value)
    }

    public static let zero = MothTextOffset(rawValue: 0)

    public static func < (lhs: MothTextOffset, rhs: MothTextOffset) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Half-open absolute UTF-8 byte range in a Moth source buffer.
public struct MothTextRange: Hashable, Sendable, Codable {
    public var start: MothTextOffset
    public var end: MothTextOffset

    public init(start: MothTextOffset, end: MothTextOffset) {
        if start <= end {
            self.start = start
            self.end = end
        } else {
            self.start = end
            self.end = start
        }
    }

    public init(start: Int, end: Int) {
        self.init(start: MothTextOffset(rawValue: start), end: MothTextOffset(rawValue: end))
    }

    public init(start: MothTextOffset, length: Int) {
        self.init(start: start, end: MothTextOffset(rawValue: start.rawValue + max(0, length)))
    }

    public var length: Int { max(0, end.rawValue - start.rawValue) }
    public var isEmpty: Bool { length == 0 }

    public func clamped(toUTF8Count count: Int) -> MothTextRange {
        let upper = max(0, count)
        let clampedStart = min(max(0, start.rawValue), upper)
        let clampedEnd = min(max(clampedStart, end.rawValue), upper)
        return MothTextRange(start: clampedStart, end: clampedEnd)
    }
}

/// Monotonic revision of authoritative Moth buffer content.
public struct MothBufferRevision: Hashable, Sendable, Codable, Comparable, RawRepresentable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let initial = MothBufferRevision(rawValue: 0)

    public static func < (lhs: MothBufferRevision, rhs: MothBufferRevision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
