import Foundation
import Synchronization

/// The picked export folder and its UI state. Never turns an error into "no folder" (spec, Error handling; design §6).
public final class FolderAccess: Sendable {
    private let settings: AppSettings
    private let current: Mutex<FolderState>
    private let folder: Mutex<BookmarkedFolder?>

    public init(settings: AppSettings) {
        self.settings = settings
        folder = Mutex(settings.folderBookmark.map { Self.makeFolder(bookmark: $0, settings: settings) })
        current = Mutex(Self.persistedState(settings))
    }

    public var state: FolderState {
        current.withLock { $0 }
    }

    /// Resolves the saved bookmark now (at boot and on app open).
    @discardableResult
    public func refresh() -> FolderState {
        guard let folder = folder.withLock({ $0 }) else { return setState(.none) }
        do {
            let url = try folder.resolvedURL()
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path) else {
                return markLost(String(describing: ExportFolderError.bookmarkUnresolvable("folder no longer exists: \(url.path)")))
            }
            return markValid(displayPath: FolderDisplayPath.make(from: url))
        } catch {
            return markLost(String(describing: error))
        }
    }

    /// Saves the folder the picker returned. Throws the real error and keeps the previous folder when the new one can't be bookmarked or resolved.
    @discardableResult
    public func savePickedFolder(_ url: URL) throws -> FolderState {
        let bookmark = try BookmarkedFolder.makeBookmark(forPickedFolder: url)
        let resolved = try BookmarkedFolder(bookmarkData: bookmark).resolvedURL()
        settings.folderBookmark = bookmark
        folder.withLock { $0 = Self.makeFolder(bookmark: bookmark, settings: settings) }
        return markValid(displayPath: FolderDisplayPath.make(from: resolved))
    }

    /// The runner's destination: nil only when no folder was ever picked. A lost folder still gets one, so the run records the real error, and a folder that comes back recovers by itself.
    public func destination() -> (any ExportDestination)? {
        guard let folder = folder.withLock({ $0 }) else { return nil }
        return ObservedFolderDestination(
            folder: folder,
            onLost: { [self] errorText in _ = markLost(errorText) },
            onWritten: { [self] in markWrittenIfLost() }
        )
    }

    static func makeFolder(bookmark: Data, settings: AppSettings) -> BookmarkedFolder {
        BookmarkedFolder(bookmarkData: bookmark) { refreshed in settings.folderBookmark = refreshed }
    }

    static func persistedState(_ settings: AppSettings) -> FolderState {
        guard settings.folderBookmark != nil else { return .none }
        if let errorText = settings.folderLostError { return .lost(errorText: errorText) }
        return .valid(displayPath: settings.folderDisplayPath ?? "")
    }

    private func markLost(_ errorText: String) -> FolderState {
        settings.folderLostError = errorText
        return setState(.lost(errorText: errorText))
    }

    private func markValid(displayPath: String) -> FolderState {
        settings.folderLostError = nil
        settings.folderDisplayPath = displayPath
        return setState(.valid(displayPath: displayPath))
    }

    private func markWrittenIfLost() {
        guard state.isLost else { return }
        settings.folderLostError = nil
        setState(.valid(displayPath: settings.folderDisplayPath ?? ""))
    }

    @discardableResult
    private func setState(_ newState: FolderState) -> FolderState {
        current.withLock { $0 = newState }
        return newState
    }
}

/// Wraps the picked folder so a write that finds it gone flips the UI to "Folder lost" with the real error.
struct ObservedFolderDestination: ExportDestination {
    let folder: BookmarkedFolder
    let onLost: @Sendable (String) -> Void
    let onWritten: @Sendable () -> Void

    func write(_ data: Data, to relativePath: String) throws {
        do {
            try folder.write(data, to: relativePath)
            onWritten()
        } catch let error as ExportFolderError {
            if case .bookmarkUnresolvable = error { onLost(String(describing: error)) }
            throw error
        }
    }
}

/// A short path the person recognises from the Files app.
public enum FolderDisplayPath {
    public static func make(from url: URL) -> String {
        let components = url.standardizedFileURL.pathComponents
        if let index = components.firstIndex(of: "com~apple~CloudDocs") {
            return (["iCloud Drive"] + components[(index + 1)...]).joined(separator: "/")
        }
        if let index = components.firstIndex(where: { $0.hasPrefix("iCloud~") }),
           components.count > index + 1, components[index + 1] == "Documents" {
            let appName = components[index].split(separator: "~").last.map { String($0).capitalized } ?? components[index]
            return ([appName] + components[(index + 2)...]).joined(separator: "/")
        }
        return components.suffix(2).joined(separator: "/")
    }
}
