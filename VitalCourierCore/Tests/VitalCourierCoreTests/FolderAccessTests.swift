import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct FolderAccessTests {
    func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func withoutABookmarkThereIsNoFolderAndNoDestination() {
        let access = FolderAccess(settings: AppSettings(storage: InMemoryStorage()))

        #expect(access.state == .none)
        #expect(access.refresh() == .none)
        #expect(access.destination() == nil)
    }

    @Test func aPickedFolderIsSavedResolvedAndRemembered() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = InMemoryStorage()
        let access = FolderAccess(settings: AppSettings(storage: storage))

        let state = try access.savePickedFolder(folder)

        let expectedPath = folder.standardizedFileURL.pathComponents.suffix(2).joined(separator: "/")
        #expect(state == .valid(displayPath: expectedPath))
        #expect(FolderAccess(settings: AppSettings(storage: storage)).state == .valid(displayPath: expectedPath))
        #expect(access.refresh() == .valid(displayPath: expectedPath))
        try #require(access.destination()).write(Data("x".utf8), to: "Vital Courier/README.md")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Vital Courier/README.md").path))
    }

    @Test func refreshFlagsADeletedFolderAsLostWithTheRealError() throws {
        let folder = try makeTemporaryFolder()
        let storage = InMemoryStorage()
        let access = FolderAccess(settings: AppSettings(storage: storage))
        try access.savePickedFolder(folder)
        try FileManager.default.removeItem(at: folder)

        let state = access.refresh()

        guard case .lost(let errorText) = state else {
            Issue.record("expected .lost, got \(state)")
            return
        }
        #expect(!errorText.isEmpty)
        #expect(FolderAccess(settings: AppSettings(storage: storage)).state == state)
        #expect(access.destination() != nil)
    }

    @Test func aWriteThatLosesTheFolderFlipsTheStateWithTheRealError() throws {
        let folder = try makeTemporaryFolder()
        let access = FolderAccess(settings: AppSettings(storage: InMemoryStorage()))
        try access.savePickedFolder(folder)
        let destination = try #require(access.destination())
        try FileManager.default.removeItem(at: folder)

        #expect(throws: ExportFolderError.self) {
            try destination.write(Data("x".utf8), to: "Vital Courier/README.md")
        }
        guard case .lost(let errorText) = access.state else {
            Issue.record("expected .lost, got \(access.state)")
            return
        }
        #expect(errorText.contains("bookmarkUnresolvable"))
    }

    @Test func aLaterSuccessfulWriteRestoresTheFolder() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = InMemoryStorage()
        let settings = AppSettings(storage: storage)
        try FolderAccess(settings: settings).savePickedFolder(folder)
        settings.folderLostError = "bookmarkUnresolvable(\"offline\")"
        let access = FolderAccess(settings: settings)
        #expect(access.state.isLost)

        try #require(access.destination()).write(Data("x".utf8), to: "Vital Courier/README.md")

        #expect(access.state == .valid(displayPath: folder.standardizedFileURL.pathComponents.suffix(2).joined(separator: "/")))
        #expect(settings.folderLostError == nil)
    }

    @Test func aFailedPickKeepsThePreviousFolder() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let access = FolderAccess(settings: AppSettings(storage: InMemoryStorage()))
        let saved = try access.savePickedFolder(folder)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        #expect(throws: (any Error).self) { try access.savePickedFolder(missing) }
        #expect(access.state == saved)
    }

    @Test func displayPathsReadLikeTheFilesApp() {
        #expect(FolderDisplayPath.make(from: URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Notes/Health")) == "iCloud Drive/Notes/Health")
        #expect(FolderDisplayPath.make(from: URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs")) == "iCloud Drive")
        #expect(FolderDisplayPath.make(from: URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/iCloud~md~obsidian/Documents/Vault/Health")) == "Obsidian/Vault/Health")
        #expect(FolderDisplayPath.make(from: URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage/Exports")) == "File Provider Storage/Exports")
    }
}
