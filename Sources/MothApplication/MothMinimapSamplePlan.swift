// SPDX-License-Identifier: MPL-2.0
//
// MothMinimapSamplePlan.swift
//
// C2.5F: height-bounded minimap sampling without shaping or wrap traversal.

import Foundation

struct MothMinimapSample: Hashable, Sendable {
    let rowIndex: Int
    let logicalLineIndex: Int
    let isActiveLineSample: Bool
}

struct MothMinimapSamplePlan: Hashable, Sendable {
    let samples: [MothMinimapSample]

    init(
        logicalLineCount: Int,
        activeLogicalLineIndex: Int,
        availableHeight: Int,
        rowStride: Int = 6
    ) {
        let lineCount = max(0, logicalLineCount)
        let capacity = max(0, availableHeight) / max(1, rowStride)
        let rowCount = min(lineCount, capacity)
        guard rowCount > 0 else {
            samples = []
            return
        }

        let activeLine = min(
            max(0, activeLogicalLineIndex),
            max(0, lineCount - 1)
        )
        let activeRow: Int
        if rowCount == 1 || lineCount <= 1 {
            activeRow = 0
        } else {
            activeRow = Int(
                (
                    Double(activeLine)
                        * Double(rowCount - 1)
                        / Double(lineCount - 1)
                ).rounded(.toNearestOrAwayFromZero)
            )
        }

        var result: [MothMinimapSample] = []
        result.reserveCapacity(rowCount)
        for row in 0..<rowCount {
            let line: Int
            if rowCount == 1 || lineCount <= 1 {
                line = 0
            } else {
                line = Int(
                    (
                        Double(row)
                            * Double(lineCount - 1)
                            / Double(rowCount - 1)
                    ).rounded(.toNearestOrAwayFromZero)
                )
            }
            result.append(
                MothMinimapSample(
                    rowIndex: row,
                    logicalLineIndex: line,
                    isActiveLineSample: row == activeRow
                )
            )
        }
        samples = result
    }
}
