import XCTest
@testable import MothWorkspace
import MothEditor
import MothTextCore

final class MothWorkspaceTests: XCTestCase {
    func testWorkspaceOwnsActiveViewPolicy() {
        let view = MothEditorViewState(bufferID: MothBufferID())
        let workspace = MothWorkspaceState(editorViews: [view], activeViewID: view.id)
        XCTAssertEqual(workspace.activeViewID, view.id)
    }
}
