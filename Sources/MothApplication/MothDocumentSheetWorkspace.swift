// SPDX-License-Identifier: MPL-2.0
//
// MothDocumentSheetWorkspace.swift
//
// M3A product-owned multi-document workspace state. Luna projects tab geometry,
// interaction, overflow, and accessibility; Moth owns document identity, history,
// views, file policy, activation, closing, and session-facing ordering.

import Foundation
import LunaUI
import MothEditor
import MothWorkspace

public struct MothDocumentSheetID: Hashable, Sendable, RawRepresentable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "MothDocumentSheetID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public static func make() -> MothDocumentSheetID {
        MothDocumentSheetID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }
}

public struct MothDocumentSheet: Sendable {
    public let id: MothDocumentSheetID
    public var document: MothFileDocument
    public var primaryView: MothEditorViewState
    public var secondaryView: MothEditorViewState
    public var findPanelState: LunaFindPanelState

    public init(
        id: MothDocumentSheetID = .make(),
        document: MothFileDocument,
        primaryView: MothEditorViewState,
        secondaryView: MothEditorViewState,
        findPanelState: LunaFindPanelState = LunaFindPanelState()
    ) {
        self.id = id
        self.document = document
        self.primaryView = primaryView
        self.secondaryView = secondaryView
        self.findPanelState = findPanelState
    }
}

public struct MothDocumentSheetCollection: Sendable {
    public private(set) var sheets: [MothDocumentSheet]
    public private(set) var activeSheetID: MothDocumentSheetID?

    public init(
        sheets: [MothDocumentSheet] = [],
        activeSheetID: MothDocumentSheetID? = nil
    ) {
        self.sheets = sheets
        self.activeSheetID = activeSheetID
        normalize()
    }

    public var count: Int { sheets.count }
    public var isEmpty: Bool { sheets.isEmpty }
    public var ids: [MothDocumentSheetID] { sheets.map(\.id) }

    public var activeIndex: Int? {
        guard let activeSheetID else { return nil }
        return sheets.firstIndex { $0.id == activeSheetID }
    }

    public var activeSheet: MothDocumentSheet? {
        guard let activeSheetID else { return nil }
        return sheet(with: activeSheetID)
    }

    public func sheet(with id: MothDocumentSheetID) -> MothDocumentSheet? {
        sheets.first { $0.id == id }
    }

    public mutating func installInitial(
        document: MothFileDocument,
        primaryView: MothEditorViewState,
        secondaryView: MothEditorViewState,
        findPanelState: LunaFindPanelState = LunaFindPanelState()
    ) -> MothDocumentSheetID {
        precondition(sheets.isEmpty, "Initial sheet may only be installed once")
        let sheet = MothDocumentSheet(
            document: document,
            primaryView: primaryView,
            secondaryView: secondaryView,
            findPanelState: findPanelState
        )
        sheets = [sheet]
        activeSheetID = sheet.id
        return sheet.id
    }

    @discardableResult
    public mutating func append(
        document: MothFileDocument,
        primaryView: MothEditorViewState,
        secondaryView: MothEditorViewState,
        findPanelState: LunaFindPanelState = LunaFindPanelState()
    ) -> MothDocumentSheetID {
        let sheet = MothDocumentSheet(
            document: document,
            primaryView: primaryView,
            secondaryView: secondaryView,
            findPanelState: findPanelState
        )
        sheets.append(sheet)
        activeSheetID = sheet.id
        return sheet.id
    }

    @discardableResult
    public mutating func activate(_ id: MothDocumentSheetID) -> Bool {
        guard sheets.contains(where: { $0.id == id }) else { return false }
        let changed = activeSheetID != id
        activeSheetID = id
        return changed
    }

    @discardableResult
    public mutating func update(
        id: MothDocumentSheetID,
        document: MothFileDocument,
        primaryView: MothEditorViewState,
        secondaryView: MothEditorViewState,
        findPanelState: LunaFindPanelState? = nil
    ) -> Bool {
        guard let index = sheets.firstIndex(where: { $0.id == id }) else {
            return false
        }
        sheets[index].document = document
        sheets[index].primaryView = primaryView
        sheets[index].secondaryView = secondaryView
        if let findPanelState {
            sheets[index].findPanelState = findPanelState
        }
        return true
    }

    public mutating func remove(
        _ id: MothDocumentSheetID
    ) -> (removed: MothDocumentSheet, nextActiveID: MothDocumentSheetID?)? {
        guard let index = sheets.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = sheets.remove(at: index)
        let next: MothDocumentSheetID?
        if sheets.isEmpty {
            next = nil
        } else {
            next = sheets[min(index, sheets.count - 1)].id
        }
        if activeSheetID == id || activeSheetID == nil {
            activeSheetID = next
        }
        normalize()
        return (removed, activeSheetID)
    }

    public mutating func normalize() {
        let ids = Set(sheets.map(\.id))
        if let activeSheetID, ids.contains(activeSheetID) {
            return
        }
        activeSheetID = sheets.first?.id
    }
}
