// SPDX-License-Identifier: MPL-2.0
import Foundation
import LunaUI

public struct MothDocumentVisualRowIndexKey: Hashable, Sendable {
    public let presentationKey: MothDocumentPresentationKey
    public let viewportWidth: Int
    public let wrapMode: LunaStaticTextWrapMode
    public init(presentationKey: MothDocumentPresentationKey, viewportWidth: Int, wrapMode: LunaStaticTextWrapMode) {
        self.presentationKey = presentationKey
        self.viewportWidth = max(0, viewportWidth)
        self.wrapMode = wrapMode
    }
}

public final class MothDocumentVisualRowIndexStore: @unchecked Sendable {
    private let lock = NSLock()
    private var indices: [MothDocumentVisualRowIndexKey: LunaStaticTextVisualRowIndex] = [:]
    public init() {}

    public func index(for key: MothDocumentVisualRowIndexKey) -> LunaStaticTextVisualRowIndex? {
        lock.withLock { indices[key] }
    }

    @discardableResult
    public func index(for key: MothDocumentVisualRowIndexKey, build: () -> LunaStaticTextVisualRowIndex) -> LunaStaticTextVisualRowIndex {
        lock.withLock {
            if let existing = indices[key] { return existing }
            let created = build()
            indices[key] = created
            return created
        }
    }

    public func invalidate(presentationKey: MothDocumentPresentationKey) {
        lock.withLock { indices = indices.filter { $0.key.presentationKey != presentationKey } }
    }

    public func invalidate(documentID: String) {
        lock.withLock { indices = indices.filter { $0.key.presentationKey.documentID != documentID } }
    }

    public func removeAll() { lock.withLock { indices.removeAll(keepingCapacity: false) } }
    public var count: Int { lock.withLock { indices.count } }
}
