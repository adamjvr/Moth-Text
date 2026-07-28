// SPDX-License-Identifier: MPL-2.0
//
// MothPaneInteractionSnapshot.swift
//
// C2.5I: one pane geometry/presentation snapshot per host interaction.

import LunaCore
import LunaUI

struct MothPaneInteractionSnapshot {
    let layout: LunaPaneContainerLayout
    let surfaces: [(paneID: LunaPaneID, surface: MothPaneEditorSurface)]

    func surface(
        at point: LunaPointI
    ) -> (paneID: LunaPaneID, surface: MothPaneEditorSurface)? {
        surfaces.first {
            $0.surface.contentFrame.contentBounds.contains(
                x: point.x,
                y: point.y
            )
        }
    }

    func surface(
        forTextSurfaceID surfaceID: LunaNodeID?
    ) -> (paneID: LunaPaneID, surface: MothPaneEditorSurface)? {
        guard let surfaceID else { return nil }
        return surfaces.first { $0.surface.textView.id == surfaceID }
    }
}
