// SPDX-License-Identifier: MPL-2.0
//
// MothApplicationFrameDamage.swift
//
// C2.5D2 bounded application-frame damage planning.

import LunaCore
import LunaHostCore
import LunaRender

public struct MothApplicationFrameGeometry {
    public var framebufferBounds: LunaRectI
    public var menuBarBounds: LunaRectI
    public var documentBarBounds: LunaRectI
    public var sidebarBounds: LunaRectI
    public var paneBounds: LunaRectI
    public var minimapBounds: LunaRectI
    public var statusBounds: LunaRectI
    public var sidebarSeparatorBounds: LunaRectI
    public var contentTopSeparatorBounds: LunaRectI
    public var accentRuleBounds: LunaRectI

    public init(framebufferSize: LunaSizeI) {
        let width = max(1, framebufferSize.width)
        let height = max(1, framebufferSize.height)
        let statusHeight = 24
        let sidebarWidth = min(260, max(150, width / 4))
        let minimapWidth = min(110, max(60, width / 10))
        let contentTop = 68
        let contentHeight = max(1, height - contentTop - statusHeight)
        let minimapLeft = max(sidebarWidth + 1, width - minimapWidth)

        framebufferBounds = LunaRectI(x: 0, y: 0, w: width, h: height)
        menuBarBounds = LunaRectI(x: 0, y: 0, w: width, h: 30)
        documentBarBounds = LunaRectI(x: 0, y: 30, w: width, h: 38)
        sidebarBounds = LunaRectI(x: 0, y: contentTop, w: sidebarWidth, h: contentHeight)
        paneBounds = LunaRectI(
            x: sidebarWidth + 1,
            y: contentTop,
            w: max(1, width - sidebarWidth - minimapWidth - 2),
            h: contentHeight
        )
        minimapBounds = LunaRectI(
            x: minimapLeft,
            y: contentTop,
            w: minimapWidth,
            h: contentHeight
        )
        statusBounds = LunaRectI(
            x: 0,
            y: max(0, height - statusHeight),
            w: width,
            h: statusHeight
        )
        sidebarSeparatorBounds = LunaRectI(
            x: sidebarWidth,
            y: contentTop,
            w: 1,
            h: contentHeight
        )
        contentTopSeparatorBounds = LunaRectI(
            x: 0,
            y: contentTop - 1,
            w: width,
            h: 1
        )
        accentRuleBounds = LunaRectI(
            x: 10,
            y: 63,
            w: min(180, max(40, width / 5)),
            h: 3
        )
    }
}

public enum MothApplicationFrameDamageKind: String, Hashable, Sendable {
    case fullScene
    case documentEdit
    case paneVisual
}

public struct MothApplicationFrameDamagePlan {
    public var kind: MothApplicationFrameDamageKind
    public var path: LunaFrameRenderPath
    public var regions: [LunaRectI]
    public var cacheMissReason: LunaFrameCacheMissReason?

    public init(
        kind: MothApplicationFrameDamageKind,
        path: LunaFrameRenderPath,
        regions: [LunaRectI],
        cacheMissReason: LunaFrameCacheMissReason? = nil
    ) {
        self.kind = kind
        self.path = path
        self.regions = regions.filter { !$0.isEmpty }
        self.cacheMissReason = cacheMissReason
    }

    public static func make(
        invalidations: LunaFrameInvalidationSet,
        geometry: MothApplicationFrameGeometry,
        hasCompatibleCache: Bool,
        hasActiveOverlay: Bool
    ) -> MothApplicationFrameDamagePlan {
        let reasons = invalidations.reasons

        let documentReasons: Set<LunaInvalidationReason> = [
            .textInput,
            .documentChanged,
            .selectionChanged,
        ]
        let isDocumentEdit = reasons.contains(.textInput)
            && reasons.isSubset(of: documentReasons)

        let paneReasons: Set<LunaInvalidationReason> = [
            .scrollChanged,
            .selectionChanged,
            .caretBlink,
        ]
        let isPaneVisual = !reasons.isEmpty
            && reasons.isSubset(of: paneReasons)

        guard isDocumentEdit || isPaneVisual else {
            return MothApplicationFrameDamagePlan(
                kind: .fullScene,
                path: .fullScene,
                regions: [geometry.framebufferBounds],
                cacheMissReason: .notApplicable
            )
        }

        guard !hasActiveOverlay else {
            return MothApplicationFrameDamagePlan(
                kind: .fullScene,
                path: .fullScene,
                regions: [geometry.framebufferBounds],
                cacheMissReason: .transientOverlayActive
            )
        }

        guard hasCompatibleCache else {
            return MothApplicationFrameDamagePlan(
                kind: .fullScene,
                path: .fullScene,
                regions: [geometry.framebufferBounds],
                cacheMissReason: .cacheAbsent
            )
        }

        if isDocumentEdit {
            return MothApplicationFrameDamagePlan(
                kind: .documentEdit,
                path: .partialDamage,
                regions: [
                    geometry.documentBarBounds,
                    geometry.paneBounds,
                    geometry.minimapBounds,
                    geometry.statusBounds,
                ]
            )
        }

        return MothApplicationFrameDamagePlan(
            kind: .paneVisual,
            path: .partialDamage,
            regions: [
                geometry.paneBounds,
                geometry.minimapBounds,
                geometry.statusBounds,
            ]
        )
    }

    public var damagedPixelCount: Int {
        regions.reduce(into: 0) { total, region in
            total += max(0, region.w) * max(0, region.h)
        }
    }
}

/// Moth-owned complete-frame backing used only as a restoration source.
struct MothApplicationStaticFrameCache {
    var framebuffer: LunaFramebuffer

    init(size: LunaSizeI) {
        framebuffer = LunaFramebuffer(width: size.width, height: size.height)
    }

    func matches(size: LunaSizeI) -> Bool {
        framebuffer.width == size.width && framebuffer.height == size.height
    }

    @discardableResult
    func restore(
        into destination: inout LunaFramebuffer,
        regions: [LunaRectI]
    ) -> Int {
        destination.copyPixels(from: framebuffer, in: regions)
    }

    mutating func replace(with source: LunaFramebuffer) {
        framebuffer.copyPixels(from: source)
    }

    mutating func update(
        from source: LunaFramebuffer,
        regions: [LunaRectI]
    ) {
        _ = framebuffer.copyPixels(from: source, in: regions)
    }
}
