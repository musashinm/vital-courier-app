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
}
