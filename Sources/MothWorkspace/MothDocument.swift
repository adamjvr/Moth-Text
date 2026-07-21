// SPDX-License-Identifier: MPL-2.0
//
// MothDocument.swift
//
// Moth-owned file/document lifecycle for the first file-backed editor slice.
// Luna may provide host dialogs and reusable document chrome, but Moth owns file
// identity, encoding preservation, dirty/save policy, and the authoritative
// source buffer associated with a product document.

import Foundation
import MothEditor
import MothTextCore

public struct MothDocumentID: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

public enum MothTextEncoding: String, Hashable, Sendable, Codable, CaseIterable {
    case utf8
    case utf8WithByteOrderMark

    public var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8WithByteOrderMark: return "UTF-8 with BOM"
        }
    }
}

public struct MothFileState: Hashable, Sendable, Codable {
    public var modificationDate: Date?
    public var sizeInBytes: UInt64

    public init(modificationDate: Date? = nil, sizeInBytes: UInt64 = 0) {
        self.modificationDate = modificationDate
        self.sizeInBytes = sizeInBytes
    }
}

public struct MothDecodedFile: Hashable, Sendable {
    public var url: URL
    public var text: String
    public var encoding: MothTextEncoding
    public var fileState: MothFileState

    public init(
        url: URL,
        text: String,
        encoding: MothTextEncoding,
        fileState: MothFileState
    ) {
        self.url = url.standardizedFileURL
        self.text = text
        self.encoding = encoding
        self.fileState = fileState
    }
}

public enum MothDocumentFileError: Error, Equatable, Sendable, LocalizedError {
    case notAFile(String)
    case unsupportedEncoding(String)
    case noSaveDestination
    case destinationExists(String)
    case readFailed(path: String, message: String)
    case writeFailed(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .notAFile(let path):
            return "Not a readable file: \(path)"
        case .unsupportedEncoding(let path):
            return "Moth M2.1 supports UTF-8 text only: \(path)"
        case .noSaveDestination:
            return "The document does not have a save destination"
        case .destinationExists(let path):
            return "Save As refused to overwrite an existing file without confirmation: \(path)"
        case .readFailed(let path, let message):
            return "Could not read \(path): \(message)"
        case .writeFailed(let path, let message):
            return "Could not save \(path): \(message)"
        }
    }
}

public protocol MothDocumentFileAccess: Sendable {
    func readTextFile(at url: URL) throws -> MothDecodedFile
    func writeTextFile(
        _ text: String,
        to url: URL,
        encoding: MothTextEncoding,
        atomically: Bool
    ) throws -> MothFileState
    func fileState(at url: URL) throws -> MothFileState
    func itemExists(at url: URL) -> Bool
}

/// Foundation-backed local filesystem implementation.
///
/// This is product infrastructure, not a Luna service. Native path selection is
/// still supplied through LunaHostCore's dialog boundary by MothApplication.
public struct MothLocalDocumentFileAccess: MothDocumentFileAccess, Sendable {
    public init() {}

    public func readTextFile(at url: URL) throws -> MothDecodedFile {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw MothDocumentFileError.notAFile(standardized.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: standardized, options: [.mappedIfSafe])
        } catch {
            throw MothDocumentFileError.readFailed(
                path: standardized.path,
                message: error.localizedDescription
            )
        }

        let bom = Data([0xEF, 0xBB, 0xBF])
        let hasBOM = data.starts(with: bom)
        let payload = hasBOM ? data.dropFirst(bom.count) : data[...]
        guard let text = String(data: payload, encoding: .utf8) else {
            throw MothDocumentFileError.unsupportedEncoding(standardized.path)
        }

        return MothDecodedFile(
            url: standardized,
            text: text,
            encoding: hasBOM ? .utf8WithByteOrderMark : .utf8,
            fileState: try fileState(at: standardized)
        )
    }

    public func writeTextFile(
        _ text: String,
        to url: URL,
        encoding: MothTextEncoding,
        atomically: Bool = true
    ) throws -> MothFileState {
        let standardized = url.standardizedFileURL
        var data = Data()
        if encoding == .utf8WithByteOrderMark {
            data.append(contentsOf: [0xEF, 0xBB, 0xBF])
        }
        data.append(Data(text.utf8))

        do {
            try data.write(to: standardized, options: atomically ? [.atomic] : [])
        } catch {
            throw MothDocumentFileError.writeFailed(
                path: standardized.path,
                message: error.localizedDescription
            )
        }
        return try fileState(at: standardized)
    }

    public func itemExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.standardizedFileURL.path)
    }

    public func fileState(at url: URL) throws -> MothFileState {
        let standardized = url.standardizedFileURL
        do {
            let values = try standardized.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
            ])
            if values.isRegularFile == false {
                throw MothDocumentFileError.notAFile(standardized.path)
            }
            return MothFileState(
                modificationDate: values.contentModificationDate,
                sizeInBytes: UInt64(max(0, values.fileSize ?? 0))
            )
        } catch let error as MothDocumentFileError {
            throw error
        } catch {
            throw MothDocumentFileError.readFailed(
                path: standardized.path,
                message: error.localizedDescription
            )
        }
    }
}

public struct MothDocumentSnapshot: Sendable {
    public var id: MothDocumentID
    public var fileURL: URL?
    public var displayName: String
    public var encoding: MothTextEncoding
    public var knownFileState: MothFileState?
    public var buffer: MothSourceBufferSnapshot

    public init(
        id: MothDocumentID,
        fileURL: URL?,
        displayName: String,
        encoding: MothTextEncoding,
        knownFileState: MothFileState?,
        buffer: MothSourceBufferSnapshot
    ) {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName
        self.encoding = encoding
        self.knownFileState = knownFileState
        self.buffer = buffer
    }

    public var isUntitled: Bool { fileURL == nil }
    public var isDirty: Bool { buffer.isDirty }
    public var displayPath: String { fileURL?.path ?? displayName }
}

/// One product document and its authoritative source buffer.
public final class MothFileDocument: @unchecked Sendable {
    public let id: MothDocumentID
    public let buffer: MothInMemorySourceBuffer
    public let history: MothDocumentHistory

    private let metadataLock = NSLock()
    private var fileURLStorage: URL?
    private var displayNameStorage: String
    private var encodingStorage: MothTextEncoding
    private var knownFileStateStorage: MothFileState?

    public init(
        id: MothDocumentID = MothDocumentID(),
        buffer: MothInMemorySourceBuffer,
        fileURL: URL? = nil,
        displayName: String? = nil,
        encoding: MothTextEncoding = .utf8,
        knownFileState: MothFileState? = nil,
        historyMemoryBudgetBytes: Int = MothDocumentHistory.defaultMemoryBudgetBytes
    ) {
        self.id = id
        self.buffer = buffer
        self.history = MothDocumentHistory(
            initialState: buffer.snapshot().historyState,
            memoryBudgetBytes: historyMemoryBudgetBytes
        )
        let standardizedURL = fileURL?.standardizedFileURL
        self.fileURLStorage = standardizedURL
        self.displayNameStorage = displayName
            ?? standardizedURL?.lastPathComponent.nonEmpty
            ?? "untitled"
        self.encodingStorage = encoding
        self.knownFileStateStorage = knownFileState
    }

    public convenience init(
        id: MothDocumentID = MothDocumentID(),
        untitledText: String = "",
        displayName: String = "untitled",
        encoding: MothTextEncoding = .utf8,
        historyMemoryBudgetBytes: Int = MothDocumentHistory.defaultMemoryBudgetBytes
    ) {
        self.init(
            id: id,
            buffer: MothInMemorySourceBuffer(text: untitledText),
            fileURL: nil,
            displayName: displayName,
            encoding: encoding,
            knownFileState: nil,
            historyMemoryBudgetBytes: historyMemoryBudgetBytes
        )
    }

    public func snapshot() -> MothDocumentSnapshot {
        let metadata = metadataLock.withLock {
            (
                fileURLStorage,
                displayNameStorage,
                encodingStorage,
                knownFileStateStorage
            )
        }
        return MothDocumentSnapshot(
            id: id,
            fileURL: metadata.0,
            displayName: metadata.1,
            encoding: metadata.2,
            knownFileState: metadata.3,
            buffer: buffer.snapshot()
        )
    }

    public func updateSaveIdentity(
        fileURL: URL,
        encoding: MothTextEncoding,
        fileState: MothFileState
    ) {
        metadataLock.withLock {
            let standardized = fileURL.standardizedFileURL
            fileURLStorage = standardized
            displayNameStorage = standardized.lastPathComponent.nonEmpty ?? displayNameStorage
            encodingStorage = encoding
            knownFileStateStorage = fileState
        }
    }

    public func updateKnownFileState(_ state: MothFileState?) {
        metadataLock.withLock {
            knownFileStateStorage = state
        }
    }
}

public struct MothDocumentController<FileAccess: MothDocumentFileAccess>: Sendable {
    public var fileAccess: FileAccess

    public init(fileAccess: FileAccess) {
        self.fileAccess = fileAccess
    }

    public func open(url: URL) throws -> MothFileDocument {
        let decoded = try fileAccess.readTextFile(at: url)
        return MothFileDocument(
            buffer: MothInMemorySourceBuffer(text: decoded.text),
            fileURL: decoded.url,
            displayName: decoded.url.lastPathComponent,
            encoding: decoded.encoding,
            knownFileState: decoded.fileState
        )
    }

    @discardableResult
    public func save(_ document: MothFileDocument) throws -> MothDocumentSnapshot {
        document.history.breakCoalescing()
        let snapshot = document.snapshot()
        guard let url = snapshot.fileURL else {
            throw MothDocumentFileError.noSaveDestination
        }
        return try saveAs(
            document,
            to: url,
            encoding: snapshot.encoding,
            allowsOverwrite: true
        )
    }

    @discardableResult
    public func saveAs(
        _ document: MothFileDocument,
        to url: URL,
        encoding: MothTextEncoding? = nil,
        allowsOverwrite: Bool = false
    ) throws -> MothDocumentSnapshot {
        let standardizedURL = url.standardizedFileURL
        if !allowsOverwrite && fileAccess.itemExists(at: standardizedURL) {
            throw MothDocumentFileError.destinationExists(standardizedURL.path)
        }
        document.history.breakCoalescing()
        let before = document.snapshot()
        let resolvedEncoding = encoding ?? before.encoding
        let savedState = try fileAccess.writeTextFile(
            before.buffer.text,
            to: standardizedURL,
            encoding: resolvedEncoding,
            atomically: true
        )
        document.updateSaveIdentity(
            fileURL: standardizedURL,
            encoding: resolvedEncoding,
            fileState: savedState
        )
        document.buffer.markSaved(
            historyState: before.buffer.historyState,
            revision: before.buffer.revision
        )
        return document.snapshot()
    }

    public func hasExternalChange(_ document: MothFileDocument) throws -> Bool {
        let snapshot = document.snapshot()
        guard let url = snapshot.fileURL, let known = snapshot.knownFileState else { return false }
        return try fileAccess.fileState(at: url) != known
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
