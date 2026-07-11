// SPDX-License-Identifier: MPL-2.0
import Foundation
import MothEditor
import MothTextCore

/// Product-owned workspace state. Luna may render tabs and split containers,
/// while Moth decides what documents, views, groups, and sessions mean.
public struct MothWorkspaceState: Sendable {
    public var documents: [MothFileDocument]
    public var editorViews: [MothEditorViewState]
    public var documentIDByViewID: [MothEditorViewID: MothDocumentID]
    public var activeDocumentID: MothDocumentID?
    public var activeViewID: MothEditorViewID?

    public init(
        documents: [MothFileDocument] = [],
        editorViews: [MothEditorViewState] = [],
        documentIDByViewID: [MothEditorViewID: MothDocumentID] = [:],
        activeDocumentID: MothDocumentID? = nil,
        activeViewID: MothEditorViewID? = nil
    ) {
        self.documents = documents
        self.editorViews = editorViews
        self.documentIDByViewID = documentIDByViewID
        self.activeDocumentID = activeDocumentID
        self.activeViewID = activeViewID
        normalize()
    }

    public var activeDocument: MothFileDocument? {
        guard let activeDocumentID else { return nil }
        return documents.first { $0.id == activeDocumentID }
    }

    public var activeView: MothEditorViewState? {
        guard let activeViewID else { return nil }
        return editorViews.first { $0.id == activeViewID }
    }

    public func document(with id: MothDocumentID) -> MothFileDocument? {
        documents.first { $0.id == id }
    }

    public func documentID(for viewID: MothEditorViewID) -> MothDocumentID? {
        documentIDByViewID[viewID]
    }

    public mutating func install(
        document: MothFileDocument,
        views: [MothEditorViewState],
        activeViewID: MothEditorViewID? = nil
    ) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        } else {
            documents.append(document)
        }

        for view in views {
            if let index = editorViews.firstIndex(where: { $0.id == view.id }) {
                editorViews[index] = view
            } else {
                editorViews.append(view)
            }
            documentIDByViewID[view.id] = document.id
        }

        activeDocumentID = document.id
        self.activeViewID = activeViewID.flatMap { candidate in
            views.contains { $0.id == candidate } ? candidate : nil
        } ?? views.first?.id
        normalize()
    }

    @discardableResult
    public mutating func activate(viewID: MothEditorViewID) -> Bool {
        guard editorViews.contains(where: { $0.id == viewID }) else { return false }
        let changed = activeViewID != viewID
        activeViewID = viewID
        activeDocumentID = documentIDByViewID[viewID]
        return changed
    }

    @discardableResult
    public mutating func activate(documentID: MothDocumentID) -> Bool {
        guard documents.contains(where: { $0.id == documentID }) else { return false }
        let changed = activeDocumentID != documentID
        activeDocumentID = documentID
        if let viewID = editorViews.first(where: { documentIDByViewID[$0.id] == documentID })?.id {
            activeViewID = viewID
        }
        return changed
    }

    public mutating func normalize() {
        let documentIDs = Set(documents.map(\.id))
        let viewIDs = Set(editorViews.map(\.id))
        documentIDByViewID = documentIDByViewID.filter { viewIDs.contains($0.key) && documentIDs.contains($0.value) }

        if let activeDocumentID, !documentIDs.contains(activeDocumentID) {
            self.activeDocumentID = documents.first?.id
        } else if activeDocumentID == nil {
            self.activeDocumentID = documents.first?.id
        }

        if let activeViewID, !viewIDs.contains(activeViewID) {
            self.activeViewID = editorViews.first?.id
        } else if activeViewID == nil {
            self.activeViewID = editorViews.first?.id
        }

        if let activeViewID, let mapped = documentIDByViewID[activeViewID] {
            activeDocumentID = mapped
        }
    }
}
