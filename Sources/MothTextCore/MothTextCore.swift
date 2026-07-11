// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Pure editor-domain foundation for Moth Text.
///
/// This target deliberately does not import Luna UI or platform frameworks.
/// Buffer storage, editor transactions, selections, and undo will grow here.
public enum MothTextCore {
    public static let architectureVersion = 2
}

/// Stable identity for a source buffer independent of any visible editor view.
public struct MothBufferID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Stable identity for one presentation of a buffer.
/// Multiple views may point at the same `MothBufferID` while retaining independent
/// selection, caret, scroll, and folding state.
public struct MothEditorViewID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
