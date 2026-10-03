import Foundation
import Synchronization

public protocol ExportDestination: Sendable {
    func write(_ data: Data, to relativePath: String) throws
}

public enum ExportFolderError: Error, Equatable {
    /// The folder moved, was deleted, or the provider signed out. The app asks the user to pick it again (spec, Error handling).
    case bookmarkUnresolvable(String)
    /// The file provider couldn't be reached (iCloud's helper not ready); the folder is kept and the next run retries.
    case folderTemporarilyUnavailable(String)
    case writeFailed(path: String, reason: String)
}

/// The calls that reach the picked folder's root: resolving the bookmark, making a fresh one, and probing that the root is reachable. One immutable dependency shared by `BookmarkedFolder` and `FolderAccess`, so tests can make any of the three fail the way the file provider does.
public struct FolderRootAccess: Sendable {
    public let resolve: @Sendable (Data) throws -> (url: URL, isStale: Bool)
    public let makeBookmark: @Sendable (URL) throws -> Data
    /// Returns false when the root is gone; throws the provider's real error when it can't tell.
    public let probe: @Sendable (URL) throws -> Bool

    public init(
        resolve: @escaping @Sendable (Data) throws -> (url: URL, isStale: Bool),
        makeBookmark: @escaping @Sendable (URL) throws -> Data,
        probe: @escaping @Sendable (URL) throws -> Bool
    ) {
        self.resolve = resolve
        self.makeBookmark = makeBookmark
        self.probe = probe
    }

    /// The Foundation implementations.
    public static let live = FolderRootAccess(
        resolve: { bookmark in
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutImplicitStartAccessing], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        },
        makeBookmark: { url in try BookmarkedFolder.makeBookmark(forPickedFolder: url) },
        probe: { url in try url.checkResourceIsReachable() }
    )
}

/// The folder the user picked, kept as a bookmark (spec, Units: ExportFolder).
public final class BookmarkedFolder: ExportDestination {
    private let bookmark: Mutex<Data>
    private let onBookmarkRefreshed: @Sendable (Data) -> Void
    private let rootAccess: FolderRootAccess

    public init(bookmarkData: Data, rootAccess: FolderRootAccess = .live, onBookmarkRefreshed: @escaping @Sendable (Data) -> Void = { _ in }) {
        bookmark = Mutex(bookmarkData)
        self.rootAccess = rootAccess
        self.onBookmarkRefreshed = onBookmarkRefreshed
    }

    /// Call with the URL the folder picker returned. Access starts before the bookmark is made; without it `bookmarkData` throws.
    public static func makeBookmark(forPickedFolder url: URL) throws -> Data {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves the bookmark, refreshing and reporting it when the system says it is stale. Throws `folderTemporarilyUnavailable` when the file provider can't be reached.
    public func resolvedURL() throws -> URL {
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try rootAccess.resolve(bookmark.withLock { $0 })
        } catch {
            throw Self.rootAccessFailure(error)
        }
        if resolved.isStale {
            let refreshed: Data
            do {
                refreshed = try rootAccess.makeBookmark(resolved.url)
            } catch {
                throw Self.rootAccessFailure(error, detail: "stale bookmark could not be refreshed")
            }
            bookmark.withLock { $0 = refreshed }
            onBookmarkRefreshed(refreshed)
        }
        return resolved.url
    }

    /// Checks that the root is reachable. Call with access already started. A thrown provider error is classified (temporary or lost); a `false` answer is a lost folder.
    func verifyRootReachable(_ root: URL) throws {
        let isReachable: Bool
        do {
            isReachable = try rootAccess.probe(root)
        } catch {
            throw Self.rootAccessFailure(error, detail: Self.isTemporaryProviderFailure(error) ? "folder could not be reached: \(root.path)" : "folder no longer exists: \(root.path)")
        }
        guard isReachable else {
            throw ExportFolderError.bookmarkUnresolvable("folder no longer exists: \(root.path)")
        }
    }

    /// The one place a root-access error becomes an `ExportFolderError`: temporary provider failures keep the folder, anything else is a lost folder. The text keeps the real error.
    static func rootAccessFailure(_ error: any Error, detail: String? = nil) -> ExportFolderError {
        let text = detail.map { "\($0): \(describe(error))" } ?? describe(error)
        return isTemporaryProviderFailure(error) ? .folderTemporarilyUnavailable(text) : .bookmarkUnresolvable(text)
    }

    /// NSCocoaErrorDomain 4097 (`NSXPCConnectionInterrupted`, "Couldn't communicate with a helper application.") or 4099 (`NSXPCConnectionInvalid`), on the error or anywhere in its `NSUnderlyingErrorKey` chain. The rest of the XPC range is not temporary.
    static func isTemporaryProviderFailure(_ error: any Error) -> Bool {
        let temporaryCodes: Set<Int> = [4097, 4099]
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSCocoaErrorDomain, temporaryCodes.contains(nsError.code) { return true }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// Writes atomically through `NSFileCoordinator`, creating intermediate folders.
    public func write(_ data: Data, to relativePath: String) throws {
        try Self.validate(relativePath: relativePath)
        let folder = try resolvedURL()
        let isAccessing = folder.startAccessingSecurityScopedResource()
        defer { if isAccessing { folder.stopAccessingSecurityScopedResource() } }
        try verifyRootReachable(folder)
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
            if Self.isLossOfRootFolder(failure, root: folder) {
                throw ExportFolderError.bookmarkUnresolvable(Self.describe(failure))
            }
            throw ExportFolderError.writeFailed(path: relativePath, reason: Self.describe(failure))
        }
    }

    /// Design recovery table: a Cocoa no-such-file or no-permission error whose failing URL is the selected root means the folder is lost. The same codes on a child path stay ordinary write failures. Looks through `NSUnderlyingErrorKey` too.
    static func isLossOfRootFolder(_ error: any Error, root: URL) -> Bool {
        let lossCodes: Set<Int> = [NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError, NSFileWriteNoPermissionError]
        let rootPath = root.standardizedFileURL.path
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSCocoaErrorDomain, lossCodes.contains(nsError.code) {
                let failingPath: String? = (nsError.userInfo[NSURLErrorKey] as? URL)?.standardizedFileURL.path
                    ?? (nsError.userInfo[NSFilePathErrorKey] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL.path }
                if failingPath == rootPath { return true }
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
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
