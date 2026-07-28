// SPDX-License-Identifier: MPL-2.0
//
// MothDocumentViewportPresentationStore.swift
//
// C2.5F: one projection and one virtualized layout context per document revision.

import Foundation
import LunaUI

struct MothDocumentViewportPresentationKey: Hashable, Sendable {
    let presentationKey: MothDocumentPresentationKey
    let geometryGeneration: UInt64

    init(
        presentationKey: MothDocumentPresentationKey,
        geometryGeneration: UInt64 = 0
    ) {
        self.presentationKey = presentationKey
        self.geometryGeneration = geometryGeneration
    }
}

struct MothDocumentViewportPresentation: Sendable {
    let key: MothDocumentViewportPresentationKey
    let storageSnapshot: LunaTextStorageSnapshot
    let presentation: LunaStaticTextPresentationSnapshot
    let virtualizationContext: LunaStaticTextVirtualizationContext
}

/// Bounded product-owned cache joining Moth storage projection to Luna layout.
///
/// The revision key is authoritative. A cache hit never compares or reparses the
/// document string. Construction occurs outside the lock, then uses a double-check
/// before insertion so expensive projection and shaping state are never built while
/// holding shared cache state.
final class MothDocumentViewportPresentationStore: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumRetainedRevisionsPerDocument: Int
    private var bundles: [
        MothDocumentViewportPresentationKey: MothDocumentViewportPresentation
    ] = [:]
    private var accessGeneration: UInt64 = 0
    private var access: [MothDocumentViewportPresentationKey: UInt64] = [:]
    private var buildCountStorage: UInt64 = 0

    init(maximumRetainedRevisionsPerDocument: Int = 2) {
        self.maximumRetainedRevisionsPerDocument = max(
            1,
            maximumRetainedRevisionsPerDocument
        )
    }

    func presentation(
        for key: MothDocumentViewportPresentationKey,
        buildStorageSnapshot: () -> LunaTextStorageSnapshot
    ) -> MothDocumentViewportPresentation {
        if let cached = lock.withLock({ cachedLocked(for: key) }) {
            return cached
        }

        let storageSnapshot = buildStorageSnapshot()
        let presentation = LunaStaticTextPresentationSnapshot(
            revision: key.presentationKey.revision,
            document: storageSnapshot.staticDocument
        )
        let built = MothDocumentViewportPresentation(
            key: key,
            storageSnapshot: storageSnapshot,
            presentation: presentation,
            virtualizationContext: LunaStaticTextVirtualizationContext(
                presentation: presentation,
                geometryGeneration: key.geometryGeneration
            )
        )

        return lock.withLock {
            if let cached = cachedLocked(for: key) {
                return cached
            }
            bundles[key] = built
            buildCountStorage &+= 1
            touchLocked(key)
            evictOldRevisionsLocked(
                documentID: key.presentationKey.documentID,
                protecting: key
            )
            return built
        }
    }

    func cachedPresentation(
        for key: MothDocumentViewportPresentationKey
    ) -> MothDocumentViewportPresentation? {
        lock.withLock { cachedLocked(for: key) }
    }

    func invalidate(documentID: String) {
        lock.withLock {
            let victims = bundles.keys.filter {
                $0.presentationKey.documentID == documentID
            }
            for key in victims {
                bundles.removeValue(forKey: key)
                access.removeValue(forKey: key)
            }
        }
    }

    func removeAll() {
        lock.withLock {
            bundles.removeAll(keepingCapacity: false)
            access.removeAll(keepingCapacity: false)
        }
    }

    var count: Int { lock.withLock { bundles.count } }
    var buildCount: UInt64 { lock.withLock { buildCountStorage } }

    private func cachedLocked(
        for key: MothDocumentViewportPresentationKey
    ) -> MothDocumentViewportPresentation? {
        guard let cached = bundles[key] else { return nil }
        touchLocked(key)
        return cached
    }

    private func touchLocked(_ key: MothDocumentViewportPresentationKey) {
        accessGeneration &+= 1
        access[key] = accessGeneration
    }

    private func evictOldRevisionsLocked(
        documentID: String,
        protecting protectedKey: MothDocumentViewportPresentationKey
    ) {
        while bundles.keys.filter({
            $0.presentationKey.documentID == documentID
        }).count > maximumRetainedRevisionsPerDocument {
            guard let victim = access
                .filter({ entry in
                    entry.key != protectedKey
                        && entry.key.presentationKey.documentID == documentID
                })
                .min(by: { $0.value < $1.value })?.key
            else { break }
            bundles.removeValue(forKey: victim)
            access.removeValue(forKey: victim)
        }
    }
}
