// SPDX-License-Identifier: MPL-2.0
//
// MothA1Audit.swift
//
// Product-owned A1.1 fixtures and measurement runner. Moth owns the persisted
// result schema and copies primitive values from Luna at the integration boundary.
// This avoids coupling Moth's JSON/CSV format to a framework-owned snapshot type.

import Foundation
import LunaCore
import LunaRender
import LunaUI

public enum MothA1FixtureKind: String, CaseIterable, Codable, Sendable {
    case ascii
    case unicode
    case tabs
    case wrappedParagraphs
    case longLogicalLines
}

public enum MothA1WrapConfiguration: String, CaseIterable, Codable, Sendable {
    case none
    case soft
}

public struct MothA1Fixture: Codable, Equatable, Sendable {
    public var kind: MothA1FixtureKind
    public var requestedLineCount: Int
    public var text: String

    public init(kind: MothA1FixtureKind, requestedLineCount: Int, text: String) {
        self.kind = kind
        self.requestedLineCount = max(1, requestedLineCount)
        self.text = text
    }

    public var utf8ByteCount: Int { text.utf8.count }
}

public enum MothA1FixtureGenerator {
    public static func make(
        kind: MothA1FixtureKind,
        lineCount: Int
    ) -> MothA1Fixture {
        let count = max(1, lineCount)
        var lines: [String] = []
        lines.reserveCapacity(count)

        for index in 0..<count {
            let line: String
            switch kind {
            case .ascii:
                line = String(
                    format: "%06d | let value = sample_%06d + 42",
                    index + 1,
                    index
                )
            case .unicode:
                line = String(
                    format: "%06d | café Ελληνικά 日本語 🙂 value_%06d",
                    index + 1,
                    index
                )
            case .tabs:
                line = "\(index + 1)\tfunc\titem_\(index)()\t{ return \(index) }"
            case .wrappedParagraphs:
                line = "\(index + 1): This deterministic paragraph contains enough words to exercise soft wrapping, shaped insertion positions, viewport geometry, and repeated layout work without relying on random input."
            case .longLogicalLines:
                line = "\(index + 1):" + String(repeating: " abcdefghij🙂", count: 64)
            }
            lines.append(line)
        }

        return MothA1Fixture(
            kind: kind,
            requestedLineCount: count,
            text: lines.joined(separator: "\n")
        )
    }
}

/// Moth-owned projection of the public Luna audit counters used by A1.1.
///
/// Keeping this value in Moth makes persisted reports stable even if Luna later
/// grows or reorganizes its recorder snapshot.
public struct MothA1LunaMetrics: Codable, Equatable, Sendable {
    public var measuredOperations: UInt64
    public var staticTextLayoutPasses: UInt64
    public var logicalLinesPresentedToLayout: UInt64
    public var visualRowsProduced: UInt64
    public var visibleRowsProduced: UInt64
    public var geometryRequests: UInt64
    public var completeLineGeometryRequests: UInt64
    public var suffixGeometryRequests: UInt64
    public var framebufferClears: UInt64
    public var framebufferClearBytes: UInt64
    public var framebufferCopies: UInt64
    public var framebufferCopyBytes: UInt64
    public var framebufferRectangleFills: UInt64
    public var framebufferRectanglePixels: UInt64
    public var durationsNanoseconds: [String: UInt64]

    public init(snapshot: LunaA1AuditSnapshot) {
        measuredOperations = snapshot[.measuredOperations]
        staticTextLayoutPasses = snapshot[.staticTextLayoutPasses]
        logicalLinesPresentedToLayout = snapshot[.logicalLinesPresentedToLayout]
        visualRowsProduced = snapshot[.visualRowsProduced]
        visibleRowsProduced = snapshot[.visibleRowsProduced]
        geometryRequests = snapshot[.geometryRequests]
        completeLineGeometryRequests = snapshot[.completeLineGeometryRequests]
        suffixGeometryRequests = snapshot[.suffixGeometryRequests]
        framebufferClears = snapshot[.framebufferClears]
        framebufferClearBytes = snapshot[.framebufferClearBytes]
        framebufferCopies = snapshot[.framebufferCopies]
        framebufferCopyBytes = snapshot[.framebufferCopyBytes]
        framebufferRectangleFills = snapshot[.framebufferRectangleFills]
        framebufferRectanglePixels = snapshot[.framebufferRectanglePixels]
        durationsNanoseconds = snapshot.durationsNanoseconds
    }
}

public struct MothA1AuditResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var fixtureKind: MothA1FixtureKind
    public var requestedLineCount: Int
    public var utf8ByteCount: Int
    public var paneCount: Int
    public var wrapConfiguration: MothA1WrapConfiguration
    public var sceneConstructionNanoseconds: UInt64
    public var firstRenderNanoseconds: UInt64
    public var primaryLayoutNanoseconds: UInt64
    public var secondaryLayoutNanoseconds: UInt64
    public var primaryTotalVisualRows: Int
    public var secondaryTotalVisualRows: Int
    public var primaryVisibleRows: Int
    public var secondaryVisibleRows: Int
    public var lunaMetrics: MothA1LunaMetrics

    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys]
            : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static let csvHeader = [
        "schema_version",
        "fixture_kind",
        "line_count",
        "utf8_bytes",
        "pane_count",
        "wrap",
        "scene_ns",
        "first_render_ns",
        "primary_layout_ns",
        "secondary_layout_ns",
        "primary_total_rows",
        "secondary_total_rows",
        "primary_visible_rows",
        "secondary_visible_rows",
        "luna_layout_passes",
        "luna_logical_lines",
        "luna_geometry_requests",
        "luna_suffix_requests",
    ].joined(separator: ",")

    public var csvRow: String {
        let columns: [String] = [
            schemaVersion.description,
            fixtureKind.rawValue,
            requestedLineCount.description,
            utf8ByteCount.description,
            paneCount.description,
            wrapConfiguration.rawValue,
            sceneConstructionNanoseconds.description,
            firstRenderNanoseconds.description,
            primaryLayoutNanoseconds.description,
            secondaryLayoutNanoseconds.description,
            primaryTotalVisualRows.description,
            secondaryTotalVisualRows.description,
            primaryVisibleRows.description,
            secondaryVisibleRows.description,
            lunaMetrics.staticTextLayoutPasses.description,
            lunaMetrics.logicalLinesPresentedToLayout.description,
            lunaMetrics.geometryRequests.description,
            lunaMetrics.suffixGeometryRequests.description,
        ]
        return columns.joined(separator: ",")
    }
}

public enum MothA1AuditRunner {
    public static func run(
        fixture: MothA1Fixture,
        wrap: MothA1WrapConfiguration,
        framebufferSize: LunaSizeI = LunaSizeI(width: 1100, height: 720)
    ) -> MothA1AuditResult {
        let recorder = LunaA1AuditRecorder.shared
        recorder.reset()
        let clock = ContinuousClock()

        let sceneStart = clock.now
        var scene = MothApplicationShellScene(
            initialSize: framebufferSize,
            initialText: fixture.text
        )
        let sceneNanoseconds = sceneStart.duration(to: clock.now).mothA1Nanoseconds

        var framebuffer = LunaFramebuffer(
            width: framebufferSize.width,
            height: framebufferSize.height
        )
        let renderStart = clock.now
        scene.render(into: &framebuffer)
        let renderNanoseconds = renderStart.duration(to: clock.now).mothA1Nanoseconds

        let primary = measuredPaneLayout(
            scene: scene,
            paneID: MothApplicationShellScene.primaryPaneID,
            wrap: wrap,
            label: "moth.primary.layout"
        )
        let secondary = measuredPaneLayout(
            scene: scene,
            paneID: MothApplicationShellScene.secondaryPaneID,
            wrap: wrap,
            label: "moth.secondary.layout"
        )

        let lunaMetrics = MothA1LunaMetrics(snapshot: recorder.snapshot())
        return MothA1AuditResult(
            schemaVersion: 2,
            fixtureKind: fixture.kind,
            requestedLineCount: fixture.requestedLineCount,
            utf8ByteCount: fixture.utf8ByteCount,
            paneCount: 2,
            wrapConfiguration: wrap,
            sceneConstructionNanoseconds: sceneNanoseconds,
            firstRenderNanoseconds: renderNanoseconds,
            primaryLayoutNanoseconds: primary.nanoseconds,
            secondaryLayoutNanoseconds: secondary.nanoseconds,
            primaryTotalVisualRows: primary.layout.totalVisualRowCount,
            secondaryTotalVisualRows: secondary.layout.totalVisualRowCount,
            primaryVisibleRows: primary.layout.visibleLines.count,
            secondaryVisibleRows: secondary.layout.visibleLines.count,
            lunaMetrics: lunaMetrics
        )
    }

    private static func measuredPaneLayout(
        scene: MothApplicationShellScene,
        paneID: LunaPaneID,
        wrap: MothA1WrapConfiguration,
        label: String
    ) -> (layout: LunaStaticTextViewLayout, nanoseconds: UInt64) {
        guard var view = scene.paneTextView(for: paneID) else {
            let emptyView = LunaStaticTextView(
                id: "moth.a1.empty",
                bounds: LunaRectI(x: 0, y: 0, w: 0, h: 0),
                document: LunaStaticTextDocument(text: "")
            )
            return (emptyView.layout(), 0)
        }

        view.wrapMode = wrap == .soft ? .soft : .none
        if let provider = view.geometryProvider {
            view.geometryProvider = LunaA1CountingGeometryProvider(base: provider)
        }

        let clock = ContinuousClock()
        let start = clock.now
        let layout = LunaA1StaticTextAudit.layout(view, label: label)
        let elapsed = start.duration(to: clock.now).mothA1Nanoseconds
        return (layout, elapsed)
    }
}

private extension Duration {
    var mothA1Nanoseconds: UInt64 {
        let value = components
        guard value.seconds >= 0 else { return 0 }

        let seconds = UInt64(value.seconds)
        let whole = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        if whole.overflow { return UInt64.max }

        let fraction: UInt64
        if value.attoseconds > 0 {
            fraction = UInt64(value.attoseconds / 1_000_000_000)
        } else {
            fraction = 0
        }

        let sum = whole.partialValue.addingReportingOverflow(fraction)
        return sum.overflow ? UInt64.max : sum.partialValue
    }
}
