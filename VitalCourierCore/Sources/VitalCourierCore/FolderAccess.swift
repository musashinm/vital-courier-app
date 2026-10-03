import Foundation
import Synchronization

/// The picked export folder and its UI state. Never turns an error into "no folder" (spec, Error handling; design §6).
///
/// Every transition (in-memory state plus the settings it persists) runs under one lock. Each installed folder has a generation; work that started for an earlier folder (an export still writing, a stale-bookmark refresh) is ignored once a newer folder is installed.
public final class FolderAccess: Sendable {
    private struct Installed {
        var state: FolderState
        var folder: BookmarkedFolder?
        var generation: Int
    }

    private let settings: AppSettings
    private let installed: Mutex<Installed>

    public init(settings: AppSettings) {
        self.settings = settings
        installed = Mutex(Installed(state: Self.persistedState(settings), folder: nil, generation: 0))
        if let bookmark = settings.folderBookmark {
            let folder = makeFolder(bookmark: bookmark, generation: 0)
            installed.withLock { $0.folder = folder }
        }
    }

    public var state: FolderState {
        installed.withLock { $0.state }
    }

    /// Resolves the saved bookmark now (at boot and on app open).
    @discardableResult
    public func refresh() -> FolderState {
        let (folder, generation) = installed.withLock { ($0.folder, $0.generation) }
        guard let folder else { return state }
        do {
            let url = try folder.resolvedURL()
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path) else {
                return markLost(String(describing: ExportFolderError.bookmarkUnresolvable("folder no longer exists: \(url.path)")), generation: generation)
            }
            return markValid(displayPath: FolderDisplayPath.make(from: url), generation: generation)
        } catch {
            return markLost(String(describing: error), generation: generation)
        }
    }

    /// Saves the folder the picker returned. Throws the real error and keeps the previous folder when the new one can't be bookmarked or resolved.
    @discardableResult
    public func savePickedFolder(_ url: URL) throws -> FolderState {
        let bookmark = try BookmarkedFolder.makeBookmark(forPickedFolder: url)
        let resolved = try BookmarkedFolder(bookmarkData: bookmark).resolvedURL()
        let displayPath = FolderDisplayPath.make(from: resolved)
        return installed.withLock { installed in
            installed.generation += 1
            installed.folder = makeFolder(bookmark: bookmark, generation: installed.generation)
            settings.folderBookmark = bookmark
            settings.folderLostError = nil
            settings.folderDisplayPath = displayPath
            installed.state = .valid(displayPath: displayPath)
            return installed.state
        }
    }

    /// The runner's destination: nil only when no folder was ever picked. A lost folder still gets one, so the run records the real error, and a folder that comes back recovers by itself.
    public func destination() -> (any ExportDestination)? {
        let (folder, generation) = installed.withLock { ($0.folder, $0.generation) }
        guard let folder else { return nil }
        return ObservedFolderDestination(
            folder: folder,
            onLost: { [self] errorText in _ = markLost(errorText, generation: generation) },
            onWritten: { [self] in markWrittenIfLost(generation: generation) }
        )
    }

    /// The generation of the folder currently installed.
    var currentGeneration: Int {
        installed.withLock { $0.generation }
    }

    /// Persists a refreshed bookmark only if its folder is still the installed one.
    func recordRefreshedBookmark(_ bookmark: Data, generation: Int) {
        installed.withLock { installed in
            guard installed.generation == generation else { return }
            settings.folderBookmark = bookmark
        }
    }

    private func makeFolder(bookmark: Data, generation: Int) -> BookmarkedFolder {
        BookmarkedFolder(bookmarkData: bookmark) { [self] refreshed in
            recordRefreshedBookmark(refreshed, generation: generation)
        }
    }

    static func persistedState(_ settings: AppSettings) -> FolderState {
        guard settings.folderBookmark != nil else { return .none }
        if let errorText = settings.folderLostError { return .lost(errorText: errorText) }
        return .valid(displayPath: settings.folderDisplayPath ?? "")
    }

    func markLost(_ errorText: String, generation: Int) -> FolderState {
        installed.withLock { installed in
            guard installed.generation == generation else { return installed.state }
            settings.folderLostError = errorText
            installed.state = .lost(errorText: errorText)
            return installed.state
        }
    }

    private func markValid(displayPath: String, generation: Int) -> FolderState {
        installed.withLock { installed in
            guard installed.generation == generation else { return installed.state }
            settings.folderLostError = nil
            settings.folderDisplayPath = displayPath
            installed.state = .valid(displayPath: displayPath)
            return installed.state
        }
    }

    func markWrittenIfLost(generation: Int) {
        installed.withLock { installed in
            guard installed.generation == generation, installed.state.isLost else { return }
            settings.folderLostError = nil
            installed.state = .valid(displayPath: settings.folderDisplayPath ?? "")
        }
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
