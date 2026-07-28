// SPDX-License-Identifier: MPL-2.0
//
// MothRuntimeWorkAttribution.swift
//
// C2.5G: measured attribution for Moth's real application shell.

import Foundation
import LunaHostCore

public struct MothRuntimeWorkAttributionSnapshot: Codable, Hashable, Sendable {
    public var schemaVersion: Int = 1
    public var presentationRequestCount: UInt64 = 0
    public var presentationBuildCount: UInt64 = 0
    public var presentationCacheHitCount: UInt64 = 0
    public var paneSurfaceBuildCount: UInt64 = 0
    public var minimapPlanCount: UInt64 = 0
    public var minimapSampleCount: UInt64 = 0
    public var fullSceneFrameCount: UInt64 = 0
    public var partialDamageFrameCount: UInt64 = 0
    public var cachedAnimationFrameCount: UInt64 = 0
    public var unknownFrameCount: UInt64 = 0
    public var lunaRuntimeTracePath: String?

    public init() {}
}

public final class MothRuntimeWorkAttributionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = MothRuntimeWorkAttributionSnapshot()
    public let traceURL: URL?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        traceURL = environment["MOTH_RUNTIME_TRACE_PATH"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        storage.lunaRuntimeTracePath = environment["LUNA_RUNTIME_TRACE_PATH"]
    }

    func recordPresentationRequest(cacheHit: Bool) {
        lock.withLock {
            storage.presentationRequestCount &+= 1
            if cacheHit {
                storage.presentationCacheHitCount &+= 1
            } else {
                storage.presentationBuildCount &+= 1
            }
        }
    }

    func recordPaneSurfaceBuild() {
        lock.withLock { storage.paneSurfaceBuildCount &+= 1 }
    }

    func recordMinimapPlan(sampleCount: Int) {
        lock.withLock {
            storage.minimapPlanCount &+= 1
            storage.minimapSampleCount &+= UInt64(max(0, sampleCount))
        }
    }

    func recordFrame(path: LunaFrameRenderPath) {
        lock.withLock {
            switch path {
            case .fullScene: storage.fullSceneFrameCount &+= 1
            case .partialDamage: storage.partialDamageFrameCount &+= 1
            case .cachedAnimation: storage.cachedAnimationFrameCount &+= 1
            case .unknown: storage.unknownFrameCount &+= 1
            }
        }
    }

    public var snapshot: MothRuntimeWorkAttributionSnapshot {
        lock.withLock { storage }
    }

    public func flushIfRequested() throws {
        guard let traceURL else { return }
        let directory = traceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let temporary = directory.appendingPathComponent(".\(traceURL.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: traceURL.path) {
            _ = try FileManager.default.replaceItemAt(traceURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: traceURL)
        }
    }
}
