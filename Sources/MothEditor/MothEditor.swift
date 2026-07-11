// SPDX-License-Identifier: MPL-2.0
import Foundation
import MothTextCore

/// Editor-domain composition layer.
///
/// Moth owns source-editor behavior and product policy. Luna supplies reusable
/// rendering, input, document UI, and workspace mechanisms.
public struct MothEditorViewState: Hashable, Sendable {
    public var id: MothEditorViewID
    public var bufferID: MothBufferID
    public var firstVisibleLine: Int

    public init(
        id: MothEditorViewID = MothEditorViewID(),
        bufferID: MothBufferID,
        firstVisibleLine: Int = 0
    ) {
        self.id = id
        self.bufferID = bufferID
        self.firstVisibleLine = max(0, firstVisibleLine)
    }
}
