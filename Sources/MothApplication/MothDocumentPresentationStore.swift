// SPDX-License-Identifier: MPL-2.0
//
// MothDocumentPresentationStore.swift
//
// C2.5A: product-owned, revision-keyed sharing of Luna presentation snapshots.

import Foundation
import LunaUI

/// Stable key for one Moth document revision.
///
/// The product document model owns both components. Luna receives the revision but
/// does not interpret or mutate it.
public struct MothDocumentPresentationKey: Hashable, Sendable {
    public let documentID: String
    public let revision: UInt64

    public init(documentID: String, revision: UInt64) {
        self.documentID = documentID
        self.revision = revision
    }
}

/// Thread-safe cache of immutable Luna presentation snapshots.
///
/// Editor panes and auxiliary consumers such as the minimap request presentation
/// through this store. Requests for the same document/revision key return the same
/// snapshot object, so source parsing and logical-line projection happen once per
/// revision rather than once per pane.
///
/// Pane-local state—scrolling, viewport dimensions, selection, caret, and focus—is
/// intentionally not stored here.
public final class MothDocumentPresentationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [
        MothDocumentPresentationKey: LunaStaticTextPresentationSnapshot
    ] = [:]

    public init() {}

    /// Return the shared presentation for a document revision.
    ///
    /// Supplying different source text for an already-cached key indicates a
    /// document-model revision bug. In that case the store replaces the stale
    /// entry rather than silently returning presentation for the wrong text.
    @discardableResult
    public func presentation(
        for key: MothDocumentPresentationKey,
        sourceText: String
    ) -> LunaStaticTextPresentationSnapshot {
        lock.withLock {
            if let existing = snapshots[key],
               existing.document.text == sourceText {
                return existing
            }

            let snapshot = LunaStaticTextPresentationSnapshot(
                revision: key.revision,
                text: sourceText
            )
            snapshots[key] = snapshot
            return snapshot
        }
    }

    /// Return a cached presentation without constructing one.
    public func cachedPresentation(
        for key: MothDocumentPresentationKey
    ) -> LunaStaticTextPresentationSnapshot? {
        lock.withLock {
            snapshots[key]
        }
    }

    /// Remove all revisions belonging to one document.
    ///
    /// Call this when a document closes or when product policy decides historical
    /// revision snapshots are no longer useful.
    public func invalidate(documentID: String) {
        lock.withLock {
            snapshots = snapshots.filter { $0.key.documentID != documentID }
        }
    }

    /// Remove one specific revision.
    public func invalidate(key: MothDocumentPresentationKey) {
        _ = lock.withLock {
            snapshots.removeValue(forKey: key)
        }
    }

    /// Drop every cached presentation.
    public func removeAll() {
        lock.withLock {
            snapshots.removeAll(keepingCapacity: false)
        }
    }

    /// Current number of cached revision snapshots.
    public var count: Int {
        lock.withLock {
            snapshots.count
        }
    }
}
