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

    #expect(
      access.state == .valid(displayPath: folder.standardizedFileURL.pathComponents.suffix(2).joined(separator: "/")))
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
    #expect(
      FolderDisplayPath.make(
        from: URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Notes/Health"))
        == "iCloud Drive/Notes/Health")
    #expect(
      FolderDisplayPath.make(
        from: URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs"))
        == "iCloud Drive")
    #expect(
      FolderDisplayPath.make(
        from: URL(
          fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/iCloud~md~obsidian/Documents/Vault/Health"))
        == "Obsidian/Vault/Health")
    #expect(
      FolderDisplayPath.make(
        from: URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage/Exports"))
        == "On My iPhone/Exports")
    #expect(
      FolderDisplayPath.make(
        from: URL(
          fileURLWithPath:
            "/private/var/mobile/Containers/Shared/AppGroup/E5125041-52E5-4CC0-ABDA-B986B712A6A6/File Provider Storage")
      ) == "On My iPhone")
    #expect(
      FolderDisplayPath.make(
        from: URL(
          fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage/Health/Daily"))
        == "On My iPhone/Health/Daily")
    #expect(
      FolderDisplayPath.make(from: URL(fileURLWithPath: "/Users/someone/File Provider Storage/Exports"))
        == "File Provider Storage/Exports")
    #expect(
      FolderDisplayPath.make(
        from: URL(
          fileURLWithPath:
            "/Users/x/File Provider Storage/y/Containers/Shared/AppGroup/ABC/File Provider Storage/Exports"))
        == "On My iPhone/Exports")
    #expect(
      FolderDisplayPath.make(
        from: URL(
          fileURLWithPath:
            "/private/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage/Notes/File Provider Storage"))
        == "On My iPhone/Notes/File Provider Storage")
  }

  @Test func aWriteFromTheOldFolderDoesNotMarkTheNewFolderLost() throws {
    let oldFolder = try makeTemporaryFolder()
    let newFolder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: newFolder) }
    let settings = AppSettings(storage: InMemoryStorage())
    let access = FolderAccess(settings: settings)
    try access.savePickedFolder(oldFolder)
    let oldDestination = try #require(access.destination())
    let newState = try access.savePickedFolder(newFolder)
    try FileManager.default.removeItem(at: oldFolder)

    #expect(throws: ExportFolderError.self) {
      try oldDestination.write(Data("x".utf8), to: "Vital Courier/README.md")
    }

    #expect(access.state == newState)
    #expect(settings.folderLostError == nil)
    #expect(FolderAccess(settings: settings).state == newState)
  }

  @Test func aRefreshedBookmarkFromTheOldFolderIsNotPersisted() throws {
    let oldFolder = try makeTemporaryFolder()
    let newFolder = try makeTemporaryFolder()
    defer {
      try? FileManager.default.removeItem(at: oldFolder)
      try? FileManager.default.removeItem(at: newFolder)
    }
    let settings = AppSettings(storage: InMemoryStorage())
    let access = FolderAccess(settings: settings)
    try access.savePickedFolder(oldFolder)
    let oldGeneration = access.currentGeneration
    try access.savePickedFolder(newFolder)
    let newBookmark = try #require(settings.folderBookmark)

    access.recordRefreshedBookmark(Data([9, 9]), generation: oldGeneration)
    #expect(settings.folderBookmark == newBookmark)

    access.recordRefreshedBookmark(Data([7]), generation: access.currentGeneration)
    #expect(settings.folderBookmark == Data([7]))
  }

  @Test func concurrentLossAndRecoveryKeepStateAndPersistedErrorTogether() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let settings = AppSettings(storage: InMemoryStorage())
    let access = FolderAccess(settings: settings)
    try access.savePickedFolder(folder)
    let generation = access.currentGeneration

    for round in 0..<200 {
      DispatchQueue.concurrentPerform(iterations: 16) { index in
        if index.isMultiple(of: 2) {
          _ = access.markLost("error \(round)-\(index)", generation: generation)
        } else {
          access.markWrittenIfLost(generation: generation)
        }
      }
      let persistedError = settings.folderLostError
      switch access.state {
      case .lost(let errorText): #expect(persistedError == errorText)
      case .valid: #expect(persistedError == nil)
      case .none: Issue.record("a folder is installed, state cannot be none")
      }
    }
  }

  private func makeAccess(
    _ scripted: ScriptedRootAccess, settings: AppSettings = AppSettings(storage: InMemoryStorage())
  ) -> FolderAccess {
    FolderAccess(settings: settings, rootAccess: scripted.access)
  }

  @Test func aTemporaryResolveFailureKeepsTheFolderValid() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let settings = AppSettings(storage: InMemoryStorage())
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted, settings: settings)
    let valid = try access.savePickedFolder(folder)
    scripted.fail(.resolve)

    let result = access.refreshReportingTemporaryFailure()

    #expect(result.state == valid)
    #expect(try #require(result.temporaryFailure).contains("helper application"))
    #expect(access.state == valid)
    #expect(settings.folderLostError == nil)
    #expect(access.refresh() == valid)
  }

  @Test func aTemporaryStaleRefreshFailureDoesNotMarkTheFolderLost() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let settings = AppSettings(storage: InMemoryStorage())
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted, settings: settings)
    let valid = try access.savePickedFolder(folder)
    scripted.fail(.staleRefresh)

    let result = access.refreshReportingTemporaryFailure()

    #expect(result.state == valid)
    #expect(result.temporaryFailure != nil)
    #expect(settings.folderLostError == nil)
  }

  @Test func aTemporaryProbeFailureDoesNotMarkTheFolderLost() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let settings = AppSettings(storage: InMemoryStorage())
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted, settings: settings)
    let valid = try access.savePickedFolder(folder)
    scripted.fail(.probe)

    let result = access.refreshReportingTemporaryFailure()

    #expect(result.state == valid)
    #expect(result.temporaryFailure != nil)
    #expect(settings.folderLostError == nil)
  }

  @Test func aRealLossStillMarksTheFolderLostWhenTheProviderIsFine() throws {
    let folder = try makeTemporaryFolder()
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted)
    try access.savePickedFolder(folder)
    try FileManager.default.removeItem(at: folder)

    let result = access.refreshReportingTemporaryFailure()

    #expect(result.state.isLost)
    #expect(result.temporaryFailure == nil)
  }

  @Test func aTemporaryWriteFailureKeepsTheFolderValidAndIsNotReportedAsLost() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let settings = AppSettings(storage: InMemoryStorage())
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted, settings: settings)
    let valid = try access.savePickedFolder(folder)
    let destination = try #require(access.destination())
    scripted.fail(.probe)

    #expect {
      try destination.write(Data("x".utf8), to: "Vital Courier/README.md")
    } throws: { error in
      if case ExportFolderError.folderTemporarilyUnavailable = error { true } else { false }
    }

    #expect(access.state == valid)
    #expect(settings.folderLostError == nil)
  }

  @Test func aTemporaryRefreshThatFinishesAfterTheFolderWasReplacedLeavesTheNewFolderAlone() throws {
    let oldFolder = try makeTemporaryFolder()
    let newFolder = try makeTemporaryFolder()
    defer {
      try? FileManager.default.removeItem(at: oldFolder)
      try? FileManager.default.removeItem(at: newFolder)
    }
    let settings = AppSettings(storage: InMemoryStorage())
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted, settings: settings)
    try access.savePickedFolder(oldFolder)
    scripted.fail(.probe)
    scripted.runBeforeFailingProbe { [scripted] in
      scripted.succeed()
      do {
        try access.savePickedFolder(newFolder)
      } catch {
        Issue.record("replacing the folder failed: \(error)")
      }
      scripted.fail(.probe)
    }

    let result = access.refreshReportingTemporaryFailure()

    #expect(result.temporaryFailure == nil)
    #expect(result.state == access.state)
    #expect(result.state == .valid(displayPath: FolderDisplayPath.make(from: newFolder)))
    #expect(settings.folderLostError == nil)
    #expect(access.refreshReportingTemporaryFailure().temporaryFailure != nil)
  }

  @Test func twoTemporaryRefreshesReportTheOutageOnce() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted)
    try access.savePickedFolder(folder)
    scripted.fail(.resolve)

    #expect(access.refreshReportingTemporaryFailure().temporaryFailure != nil)
    #expect(access.refreshReportingTemporaryFailure().temporaryFailure == nil)
  }

  @Test func aSuccessfulRefreshEndsTheOutage() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted)
    try access.savePickedFolder(folder)

    scripted.fail(.resolve)
    #expect(access.refreshReportingTemporaryFailure().temporaryFailure != nil)
    scripted.succeed()
    #expect(access.refreshReportingTemporaryFailure().temporaryFailure == nil)
    scripted.fail(.resolve)
    #expect(access.refreshReportingTemporaryFailure().temporaryFailure != nil)
  }

  @Test func aSuccessfulWriteEndsTheOutage() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted)
    try access.savePickedFolder(folder)
    let destination = try #require(access.destination())

    scripted.fail(.resolve)
    #expect(access.refreshReportingTemporaryFailure().temporaryFailure != nil)
    scripted.succeed()
    try destination.write(Data("x".utf8), to: "Vital Courier/README.md")
    scripted.fail(.resolve)
    #expect(access.refreshReportingTemporaryFailure().temporaryFailure != nil)
  }

  @Test func pickingANewFolderEndsTheOutage() throws {
    let oldFolder = try makeTemporaryFolder()
    let newFolder = try makeTemporaryFolder()
    defer {
      try? FileManager.default.removeItem(at: oldFolder)
      try? FileManager.default.removeItem(at: newFolder)
    }
    let scripted = ScriptedRootAccess()
    let access = makeAccess(scripted)
    try access.savePickedFolder(oldFolder)
    scripted.fail(.resolve)
    #expect(access.refreshReportingTemporaryFailure().temporaryFailure != nil)
    scripted.succeed()
    try access.savePickedFolder(newFolder)

    scripted.fail(.resolve)

    #expect(access.refreshReportingTemporaryFailure().temporaryFailure != nil)
  }

  @Test func aProbeThatReturnsFalseMarksTheFolderLostWithoutATemporaryFailure() throws {
    let folder = try makeTemporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let settings = AppSettings(storage: InMemoryStorage())
    let unreachable = FolderRootAccess(
      resolve: { try FolderRootAccess.live.resolve($0) },
      makeBookmark: { try FolderRootAccess.live.makeBookmark($0) },
      probe: { _ in false }
    )
    let access = FolderAccess(settings: settings, rootAccess: unreachable)
    try access.savePickedFolder(folder)

    let result = access.refreshReportingTemporaryFailure()

    guard case .lost(let errorText) = result.state else {
      Issue.record("expected .lost, got \(result.state)")
      return
    }
    #expect(errorText.contains("folder no longer exists"))
    #expect(result.temporaryFailure == nil)
    #expect(settings.folderLostError == errorText)
    #expect(access.state == result.state)
  }
}
