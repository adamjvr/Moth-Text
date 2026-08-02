// SPDX-License-Identifier: MPL-2.0
//
// MothPaneInteractionSnapshot.swift
//
// C2.5J: persistent geometry/presentation snapshots with lazy pane surfaces.

import Foundation
import LunaCore
import LunaUI

/// Exact compatibility key for a reusable interaction snapshot.
///
/// The snapshot contains pane geometry and one revision-stable presentation bundle.
/// Pane surfaces are materialized lazily and are retained only while document,
/// geometry, viewport/view state, and active-pane identity remain compatible.
struct MothPaneInteractionSnapshotKey: Hashable, Sendable {
    let documentID: String
    let documentRevision: UInt64
    let framebufferWidth: Int
    let framebufferHeight: Int
    let paneGeometryGeneration: UInt64
    let paneViewGeneration: UInt64
    let activePaneID: String
}

/// Reusable interaction state for hit testing and scrollbar/selection routing.
///
/// C2.5I constructed both pane surfaces for every host interaction. C2.5J keeps
/// the cheap pane layout and shared presentation across compatible events, then
/// constructs only the pane surface that an interaction actually touches.
final class MothPaneInteractionSnapshot: @unchecked Sendable {
    let key: MothPaneInteractionSnapshotKey
    let layout: LunaPaneContainerLayout
    let presentationBundle: MothDocumentViewportPresentation

    private var surfaces: [LunaPaneID: MothPaneEditorSurface] = [:]

    init(
        key: MothPaneInteractionSnapshotKey,
        layout: LunaPaneContainerLayout,
        presentationBundle: MothDocumentViewportPresentation
    ) {
        self.key = key
        self.layout = layout
        self.presentationBundle = presentationBundle
    }

    func contentFrame(at point: LunaPointI) -> LunaPaneContentFrame? {
        layout.contentFrames(metrics: .editor).first {
            $0.contentBounds.contains(x: point.x, y: point.y)
        }
    }

    func contentFrame(
        forTextSurfaceID surfaceID: LunaNodeID?
    ) -> LunaPaneContentFrame? {
        guard let surfaceID else { return nil }
        return layout.contentFrames(metrics: .editor).first {
            $0.nodeID.child("text-view") == surfaceID
        }
    }

    /// Return a compatible cached surface or construct exactly one target surface.
    func surface(
        for frame: LunaPaneContentFrame,
        build: () -> MothPaneEditorSurface
    ) -> (surface: MothPaneEditorSurface, didBuild: Bool) {
        if let cached = surfaces[frame.paneID] {
            return (cached, false)
        }
        let built = build()
        surfaces[frame.paneID] = built
        return (built, true)
    }
}

/// Single-entry cache. A new compatibility key replaces the previous snapshot.
///
/// The shell is single-threaded today, but the lock keeps this helper safe if host
/// event dispatch and diagnostics are separated later.
final class MothPaneInteractionSnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedSnapshot: MothPaneInteractionSnapshot?

    func cached(
        for key: MothPaneInteractionSnapshotKey
    ) -> MothPaneInteractionSnapshot? {
        lock.withLock {
            guard cachedSnapshot?.key == key else { return nil }
            return cachedSnapshot
        }
    }

    func replace(with snapshot: MothPaneInteractionSnapshot) {
        lock.withLock {
            cachedSnapshot = snapshot
        }
    }

    func removeAll() {
        lock.withLock {
            cachedSnapshot = nil
        }
    }
}
