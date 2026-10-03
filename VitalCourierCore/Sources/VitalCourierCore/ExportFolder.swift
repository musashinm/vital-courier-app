import Foundation
import Synchronization

public protocol ExportDestination: Sendable {
    func write(_ data: Data, to relativePath: String) throws
}

public enum ExportFolderError: Error, Equatable {
    /// The folder moved, was deleted, or the provider signed out. The app asks the user to pick it again (spec, Error handling).
    case bookmarkUnresolvable(String)
    case writeFailed(path: String, reason: String)
}

/// The folder the user picked, kept as a bookmark (spec, Units: ExportFolder).
public final class BookmarkedFolder: ExportDestination {
    private let bookmark: Mutex<Data>
    private let onBookmarkRefreshed: @Sendable (Data) -> Void

    public init(bookmarkData: Data, onBookmarkRefreshed: @escaping @Sendable (Data) -> Void = { _ in }) {
        bookmark = Mutex(bookmarkData)
        self.onBookmarkRefreshed = onBookmarkRefreshed
    }

    /// Call with the URL the folder picker returned. Access starts before the bookmark is made; without it `bookmarkData` throws.
    public static func makeBookmark(forPickedFolder url: URL) throws -> Data {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves the bookmark, refreshing and reporting it when the system says it is stale.
    public func resolvedURL() throws -> URL {
        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark.withLock { $0 }, options: [.withoutImplicitStartAccessing], relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            throw ExportFolderError.bookmarkUnresolvable(error.localizedDescription)
        }
        if isStale {
            let refreshed: Data
            do {
                refreshed = try Self.makeBookmark(forPickedFolder: url)
            } catch {
                throw ExportFolderError.bookmarkUnresolvable("stale bookmark could not be refreshed: \(error.localizedDescription)")
            }
            bookmark.withLock { $0 = refreshed }
            onBookmarkRefreshed(refreshed)
        }
        return url
    }

    /// Writes atomically through `NSFileCoordinator`, creating intermediate folders.
    public func write(_ data: Data, to relativePath: String) throws {
        try Self.validate(relativePath: relativePath)
        let folder = try resolvedURL()
        let isAccessing = folder.startAccessingSecurityScopedResource()
        defer { if isAccessing { folder.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw ExportFolderError.bookmarkUnresolvable("folder no longer exists: \(folder.path)")
        }
        let target = folder.appendingPathComponent(relativePath)
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.createDirectory(at: coordinatedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let failure = coordinationError ?? writeError {
            throw ExportFolderError.writeFailed(path: relativePath, reason: Self.describe(failure))
        }
    }

    /// The localized text plus the domain and code, so the app recognises a full disk in any language.
    static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]"
    }

    /// Rejects paths that could leave the picked folder: empty, absolute, or with an empty, `.` or `..` component.
    private static func validate(relativePath: String) throws {
        let reason: String?
        if relativePath.isEmpty {
            reason = "path is empty"
        } else if relativePath.hasPrefix("/") {
            reason = "path must be relative"
        } else if relativePath.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            reason = "path has an empty, \".\" or \"..\" component"
        } else {
            reason = nil
        }
        if let reason {
            throw ExportFolderError.writeFailed(path: relativePath, reason: reason)
        }
    }
}
