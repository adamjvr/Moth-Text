// SPDX-License-Identifier: MPL-2.0
//
// MothDocumentWrapIndexStore.swift
//
// C2.5B: width-keyed sharing of Luna wrap records.

import Foundation
import LunaUI

/// Cache key for one logical line in one revision at one wrap width.
public struct MothDocumentWrapIndexKey: Hashable, Sendable {
    public let presentationKey: MothDocumentPresentationKey
    public let lineIndex: Int
    public let viewportWidth: Int

    public init(
        presentationKey: MothDocumentPresentationKey,
        lineIndex: Int,
        viewportWidth: Int
    ) {
        self.presentationKey = presentationKey
        self.lineIndex = max(0, lineIndex)
        self.viewportWidth = max(0, viewportWidth)
    }
}

/// Thread-safe cache for immutable Luna soft-wrap indices.
///
/// Equal document revision, logical line, and viewport width reuse the same index
/// across panes. Pane scroll, selection, caret, and focus are deliberately absent
/// from the key.
public final class MothDocumentWrapIndexStore: @unchecked Sendable {
    private let lock = NSLock()
    private var indices: [MothDocumentWrapIndexKey: LunaStaticTextWrapIndex] = [:]

    public init() {}

    public func index(for key: MothDocumentWrapIndexKey) -> LunaStaticTextWrapIndex? {
        lock.withLock { indices[key] }
    }

    @discardableResult
    public func insert(
        _ index: LunaStaticTextWrapIndex,
        for key: MothDocumentWrapIndexKey
    ) -> LunaStaticTextWrapIndex {
        lock.withLock {
            if let existing = indices[key] {
                return existing
            }
            indices[key] = index
            return index
        }
    }

    /// Atomically retrieve or construct an index.
    @discardableResult
    public func index(
        for key: MothDocumentWrapIndexKey,
        build: () -> LunaStaticTextWrapIndex
    ) -> LunaStaticTextWrapIndex {
        lock.withLock {
            if let existing = indices[key] {
                return existing
            }
            let created = build()
            indices[key] = created
            return created
        }
    }

    /// Invalidate every width and line for one document revision.
    public func invalidate(presentationKey: MothDocumentPresentationKey) {
        lock.withLock {
            indices = indices.filter { $0.key.presentationKey != presentationKey }
        }
    }

    /// Invalidate all revisions belonging to one document.
    public func invalidate(documentID: String) {
        lock.withLock {
            indices = indices.filter {
                $0.key.presentationKey.documentID != documentID
            }
        }
    }

    public func removeAll() {
        lock.withLock {
            indices.removeAll(keepingCapacity: false)
        }
    }

    public var count: Int {
        lock.withLock { indices.count }
    }
}
