import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct ExportFolderTests {
    func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func writesNestedFilesAndReplacesThem() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = BookmarkedFolder(bookmarkData: try BookmarkedFolder.makeBookmark(forPickedFolder: folder))

        try destination.write(Data("one".utf8), to: "Vital Courier/daily/2026-09-27.md")
        try destination.write(Data("two".utf8), to: "Vital Courier/daily/2026-09-27.md")

        let written = folder.appendingPathComponent("Vital Courier/daily/2026-09-27.md")
        #expect(try String(contentsOf: written, encoding: .utf8) == "two")
    }

    @Test func aDeletedFolderIsReportedAsUnresolvable() throws {
        let folder = try makeTemporaryFolder()
        let destination = BookmarkedFolder(bookmarkData: try BookmarkedFolder.makeBookmark(forPickedFolder: folder))
        try FileManager.default.removeItem(at: folder)

        #expect {
            try destination.write(Data("x".utf8), to: "Vital Courier/README.md")
        } throws: { error in
            if case ExportFolderError.bookmarkUnresolvable = error { true } else { false }
        }
    }

    @Test func garbageBookmarkDataIsReportedAsUnresolvable() {
        let destination = BookmarkedFolder(bookmarkData: Data("not a bookmark".utf8))
        #expect {
            try destination.write(Data("x".utf8), to: "Vital Courier/README.md")
        } throws: { error in
            if case ExportFolderError.bookmarkUnresolvable = error { true } else { false }
        }
    }

    @Test func pathsLeavingTheFolderAreRejected() throws {
        let parent = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = parent.appendingPathComponent("picked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = BookmarkedFolder(bookmarkData: try BookmarkedFolder.makeBookmark(forPickedFolder: folder))

        for path in ["Vital Courier/../escape.md", "../escape.md", "/escape.md", "", "a//b.md", "./a.md"] {
            #expect {
                try destination.write(Data("x".utf8), to: path)
            } throws: { error in
                if case ExportFolderError.writeFailed = error { true } else { false }
            }
        }
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("escape.md").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func writeFailureReasonsCarryTheErrorDomainAndCode() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A plain file where the subfolder should be makes the directory creation fail.
        try Data("x".utf8).write(to: folder.appendingPathComponent("Vital Courier"))
        let destination = BookmarkedFolder(bookmarkData: try BookmarkedFolder.makeBookmark(forPickedFolder: folder))

        #expect {
            try destination.write(Data("x".utf8), to: "Vital Courier/README.md")
        } throws: { error in
            if case ExportFolderError.writeFailed(_, let reason) = error { reason.contains("[NSCocoaErrorDomain ") } else { false }
        }
    }

    private func cocoaError(code: Int, domain: String = NSCocoaErrorDomain, url: URL? = nil, path: String? = nil, underlying: NSError? = nil) -> NSError {
        var info: [String: Any] = [:]
        if let url { info[NSURLErrorKey] = url }
        if let path { info[NSFilePathErrorKey] = path }
        if let underlying { info[NSUnderlyingErrorKey] = underlying }
        return NSError(domain: domain, code: code, userInfo: info)
    }

    @Test func noPermissionOnTheRootIsALostFolder() {
        let root = URL(fileURLWithPath: "/tmp/picked")
        #expect(BookmarkedFolder.isLossOfRootFolder(cocoaError(code: NSFileWriteNoPermissionError, url: root), root: root))
        #expect(BookmarkedFolder.isLossOfRootFolder(cocoaError(code: NSFileReadNoPermissionError, path: "/tmp/picked/"), root: root))
    }

    @Test func noSuchFileOnTheRootIsALostFolder() {
        let root = URL(fileURLWithPath: "/tmp/picked")
        #expect(BookmarkedFolder.isLossOfRootFolder(cocoaError(code: NSFileNoSuchFileError, url: root), root: root))
        let wrapped = cocoaError(code: NSFileWriteUnknownError, underlying: cocoaError(code: NSFileReadNoSuchFileError, url: root))
        #expect(BookmarkedFolder.isLossOfRootFolder(wrapped, root: root))
    }

    @Test func theSameCodesOnAChildPathStayWriteFailures() {
        let root = URL(fileURLWithPath: "/tmp/picked")
        let child = root.appendingPathComponent("Vital Courier")
        #expect(!BookmarkedFolder.isLossOfRootFolder(cocoaError(code: NSFileWriteNoPermissionError, url: child), root: root))
        #expect(!BookmarkedFolder.isLossOfRootFolder(cocoaError(code: NSFileNoSuchFileError, path: child.path), root: root))
    }

    @Test func otherCodesOnTheRootStayWriteFailures() {
        let root = URL(fileURLWithPath: "/tmp/picked")
        #expect(!BookmarkedFolder.isLossOfRootFolder(cocoaError(code: NSFileWriteOutOfSpaceError, url: root), root: root))
        #expect(!BookmarkedFolder.isLossOfRootFolder(cocoaError(code: NSFileWriteNoPermissionError, domain: NSPOSIXErrorDomain, url: root), root: root))
    }

    @Test func helperNotReadyErrorsAreTemporary() {
        #expect(BookmarkedFolder.isTemporaryProviderFailure(cocoaError(code: 4097)))
        #expect(BookmarkedFolder.isTemporaryProviderFailure(cocoaError(code: 4099)))
        #expect(BookmarkedFolder.isTemporaryProviderFailure(cocoaError(code: NSFileWriteUnknownError, underlying: cocoaError(code: 4097))))
    }

    @Test func otherErrorsAreNotTemporary() {
        let root = URL(fileURLWithPath: "/tmp/picked")
        #expect(!BookmarkedFolder.isTemporaryProviderFailure(cocoaError(code: 4098)))
        #expect(!BookmarkedFolder.isTemporaryProviderFailure(cocoaError(code: NSFileNoSuchFileError, url: root)))
        #expect(!BookmarkedFolder.isTemporaryProviderFailure(cocoaError(code: NSFileReadNoSuchFileError, url: root)))
        #expect(!BookmarkedFolder.isTemporaryProviderFailure(cocoaError(code: 4097, domain: NSPOSIXErrorDomain)))
    }

    @Test func aTemporaryFailureIsNotReportedAsAFolderLoss() {
        let description = String(describing: ExportFolderError.folderTemporarilyUnavailable("Couldn’t communicate with a helper application. [NSCocoaErrorDomain 4097]"))

        #expect(RunErrorKind(error: description) == .other)
        #expect(!description.contains("bookmarkUnresolvable"))
    }

    @Test func aTemporaryResolveFailureKeepsTheRealError() throws {
        let scripted = ScriptedRootAccess()
        let destination = BookmarkedFolder(bookmarkData: Data("unused".utf8), rootAccess: scripted.access)
        scripted.fail(.resolve)

        #expect {
            try destination.write(Data("x".utf8), to: "Vital Courier/README.md")
        } throws: { error in
            guard case ExportFolderError.folderTemporarilyUnavailable(let text) = error else { return false }
            return text.contains("helper application") && text.contains("4097")
        }
    }

    @Test func aTemporaryStaleRefreshFailureIsTemporary() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scripted = ScriptedRootAccess()
        let destination = BookmarkedFolder(bookmarkData: try BookmarkedFolder.makeBookmark(forPickedFolder: folder), rootAccess: scripted.access)
        scripted.fail(.staleRefresh)

        #expect {
            try destination.write(Data("x".utf8), to: "Vital Courier/README.md")
        } throws: { error in
            guard case ExportFolderError.folderTemporarilyUnavailable(let text) = error else { return false }
            return text.contains("stale bookmark could not be refreshed") && text.contains("4097")
        }
    }

    @Test func aTemporaryProbeFailureIsTemporaryAndAFalseProbeIsALostFolder() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scripted = ScriptedRootAccess()
        let destination = BookmarkedFolder(bookmarkData: try BookmarkedFolder.makeBookmark(forPickedFolder: folder), rootAccess: scripted.access)
        scripted.fail(.probe)

        #expect {
            try destination.write(Data("x".utf8), to: "Vital Courier/README.md")
        } throws: { error in
            if case ExportFolderError.folderTemporarilyUnavailable = error { true } else { false }
        }

        let unreachable = FolderRootAccess(
            resolve: { try FolderRootAccess.live.resolve($0) },
            makeBookmark: { try FolderRootAccess.live.makeBookmark($0) },
            probe: { _ in false }
        )
        let lostDestination = BookmarkedFolder(bookmarkData: try BookmarkedFolder.makeBookmark(forPickedFolder: folder), rootAccess: unreachable)
        #expect {
            try lostDestination.write(Data("x".utf8), to: "Vital Courier/README.md")
        } throws: { error in
            guard case ExportFolderError.bookmarkUnresolvable(let text) = error else { return false }
            return text.contains("folder no longer exists")
        }
    }

    @Test func describeKeepsTheTextAndCodeOfEveryUnderlyingError() {
        let inner = NSError(domain: NSCocoaErrorDomain, code: 4097, userInfo: [NSLocalizedDescriptionKey: "Couldn’t communicate with a helper application."])
        let outer = NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [NSLocalizedDescriptionKey: "Couldn’t read.", NSUnderlyingErrorKey: inner])

        #expect(BookmarkedFolder.describe(inner) == "Couldn’t communicate with a helper application. [NSCocoaErrorDomain 4097]")
        let text = BookmarkedFolder.describe(outer)
        #expect(text.hasPrefix("Couldn’t read. [NSCocoaErrorDomain \(NSFileReadUnknownError)]; underlying: "))
        #expect(text.hasSuffix("Couldn’t communicate with a helper application. [NSCocoaErrorDomain 4097]"))
        guard case ExportFolderError.folderTemporarilyUnavailable(let recorded) = BookmarkedFolder.rootAccessFailure(outer) else {
            Issue.record("expected a temporary failure")
            return
        }
        #expect(recorded.contains("helper application") && recorded.contains("4097"))
    }
}
