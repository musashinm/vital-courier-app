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
        /// True from the first temporary provider failure until a refresh or write succeeds, so one outage is reported once.
        var isTemporarilyUnavailable = false
    }

    private let settings: AppSettings
    private let installed: Mutex<Installed>
    private let rootAccess: FolderRootAccess

    public init(settings: AppSettings, rootAccess: FolderRootAccess = .live) {
        self.settings = settings
        self.rootAccess = rootAccess
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
        refreshReportingTemporaryFailure().state
    }

    /// Like `refresh()`, and also returns the error text when the file provider couldn't be reached (iCloud's helper not ready). That is not a lost folder: the state is left as it was. The text comes back only on the transition into the outage, once until a refresh or write succeeds, so the caller records one row per outage.
    public func refreshReportingTemporaryFailure() -> (state: FolderState, temporaryFailure: String?) {
        let (folder, generation) = installed.withLock { ($0.folder, $0.generation) }
        guard let folder else { return (state, nil) }
        do {
            let url = try folder.resolvedURL()
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            try folder.verifyRootReachable(url)
            return (markValid(displayPath: FolderDisplayPath.make(from: url), generation: generation), nil)
        } catch ExportFolderError.folderTemporarilyUnavailable(let errorText) {
            return markTemporarilyUnavailable(errorText, generation: generation)
        } catch {
            return (markLost(String(describing: error), generation: generation), nil)
        }
    }

    /// Saves the folder the picker returned. Throws the real error and keeps the previous folder when the new one can't be bookmarked or resolved.
    @discardableResult
    public func savePickedFolder(_ url: URL) throws -> FolderState {
        let bookmark = try rootAccess.makeBookmark(url)
        let resolved = try BookmarkedFolder(bookmarkData: bookmark, rootAccess: rootAccess).resolvedURL()
        let displayPath = FolderDisplayPath.make(from: resolved)
        return installed.withLock { installed in
            installed.generation += 1
            installed.isTemporarilyUnavailable = false
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
        BookmarkedFolder(bookmarkData: bookmark, rootAccess: rootAccess) { [self] refreshed in
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
            installed.isTemporarilyUnavailable = false
            settings.folderLostError = nil
            settings.folderDisplayPath = displayPath
            installed.state = .valid(displayPath: displayPath)
            return installed.state
        }
    }

    /// Keeps the state as it is. Reports the text only when this is the first temporary failure since the last success.
    private func markTemporarilyUnavailable(_ errorText: String, generation: Int) -> (state: FolderState, temporaryFailure: String?) {
        installed.withLock { installed in
            guard installed.generation == generation else { return (installed.state, nil) }
            let isNewOutage = !installed.isTemporarilyUnavailable
            installed.isTemporarilyUnavailable = true
            return (installed.state, isNewOutage ? errorText : nil)
        }
    }

    /// A confirmed write ends any temporary outage, and restores a folder that was marked lost.
    func markWrittenIfLost(generation: Int) {
        installed.withLock { installed in
            guard installed.generation == generation else { return }
            installed.isTemporarilyUnavailable = false
            guard installed.state.isLost else { return }
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

/// A short path the person recognises from the Files app. The roots it names (`iCloud Drive`, `On My iPhone`) are English sentinels the App translates.
public enum FolderDisplayPath {
    public static let onMyIPhone = "On My iPhone"

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
        if let index = components.indices.first(where: { $0 >= 2 && components[$0] == "File Provider Storage" && components[$0 - 2] == "AppGroup" }) {
            return ([onMyIPhone] + components[(index + 1)...]).joined(separator: "/")
        }
        return components.suffix(2).joined(separator: "/")
    }
}
