// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaCore
@testable import MothApplication

final class MothA1AuditTests: XCTestCase {
    func testFixtureGeneratorProducesRequestedLogicalLineCount() {
        for kind in MothA1FixtureKind.allCases {
            let fixture = MothA1FixtureGenerator.make(kind: kind, lineCount: 50)
            XCTAssertEqual(fixture.requestedLineCount, 50)
            XCTAssertEqual(
                fixture.text.split(separator: "\n", omittingEmptySubsequences: false).count,
                50
            )
            XCTAssertGreaterThan(fixture.utf8ByteCount, 0)
        }
    }

    func testSmallAuditProducesProductOwnedMachineReadableMetrics() throws {
        let fixture = MothA1FixtureGenerator.make(kind: .unicode, lineCount: 50)
        let result = MothA1AuditRunner.run(
            fixture: fixture,
            wrap: .soft,
            framebufferSize: LunaSizeI(width: 900, height: 600)
        )

        XCTAssertEqual(result.schemaVersion, 2)
        XCTAssertEqual(result.requestedLineCount, 50)
        XCTAssertEqual(result.paneCount, 2)
        XCTAssertGreaterThan(result.firstRenderNanoseconds, 0)
        XCTAssertGreaterThan(result.primaryTotalVisualRows, 0)
        XCTAssertGreaterThan(result.secondaryTotalVisualRows, 0)
        XCTAssertGreaterThan(result.lunaMetrics.staticTextLayoutPasses, 0)
        XCTAssertGreaterThan(result.lunaMetrics.logicalLinesPresentedToLayout, 0)

        let encoded = try result.jsonData()
        let decoded = try JSONDecoder().decode(MothA1AuditResult.self, from: encoded)
        XCTAssertEqual(decoded, result)

        let headerColumns = MothA1AuditResult.csvHeader.split(separator: ",")
        let rowColumns = result.csvRow.split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(rowColumns.count, headerColumns.count)
    }

    func testLunaMetricsProjectionIsIndependentOfSnapshotSerialization() throws {
        let fixture = MothA1FixtureGenerator.make(kind: .ascii, lineCount: 50)
        let result = MothA1AuditRunner.run(fixture: fixture, wrap: .none)

        XCTAssertGreaterThan(result.lunaMetrics.staticTextLayoutPasses, 0)
        XCTAssertNoThrow(try JSONEncoder().encode(result.lunaMetrics))
    }

    func testFullAuditMatrixWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["MOTH_RUN_A1_FULL_AUDIT"] == "1" else {
            throw XCTSkip("Set MOTH_RUN_A1_FULL_AUDIT=1 to execute the expensive matrix")
        }

        let outputDirectory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["MOTH_A1_OUTPUT_DIR"]
                ?? ".build/a1.1-audit",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        var results: [MothA1AuditResult] = []
        for lineCount in [50, 500, 5_000, 50_000] {
            for kind in MothA1FixtureKind.allCases {
                for wrap in MothA1WrapConfiguration.allCases {
                    let fixture = MothA1FixtureGenerator.make(
                        kind: kind,
                        lineCount: lineCount
                    )
                    let result = MothA1AuditRunner.run(
                        fixture: fixture,
                        wrap: wrap
                    )
                    results.append(result)

                    let filename = "\(kind.rawValue)-\(lineCount)-\(wrap.rawValue).json"
                    try result.jsonData().write(
                        to: outputDirectory.appendingPathComponent(filename),
                        options: .atomic
                    )
                }
            }
        }

        let csvLines = [MothA1AuditResult.csvHeader] + results.map(\.csvRow)
        try (csvLines.joined(separator: "\n") + "\n").write(
            to: outputDirectory.appendingPathComponent("A1.1_RESULTS.csv"),
            atomically: true,
            encoding: .utf8
        )

        let expectedCount = 4
            * MothA1FixtureKind.allCases.count
            * MothA1WrapConfiguration.allCases.count
        XCTAssertEqual(results.count, expectedCount)
    }
}
