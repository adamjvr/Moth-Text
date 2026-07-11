// SPDX-License-Identifier: MPL-2.0
import Foundation
import MothEditor
import MothTextCore

/// Product-owned workspace state. Luna may render tabs and split containers,
/// while Moth decides what documents, views, groups, and sessions mean.
public struct MothWorkspaceState: Sendable {
    public var editorViews: [MothEditorViewState]
    public var activeViewID: MothEditorViewID?

    public init(editorViews: [MothEditorViewState] = [], activeViewID: MothEditorViewID? = nil) {
        self.editorViews = editorViews
        self.activeViewID = activeViewID
    }
}
