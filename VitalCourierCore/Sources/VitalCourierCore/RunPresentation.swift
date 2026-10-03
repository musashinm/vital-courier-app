import Foundation

/// The export folder as the UI shows it (design iOS App v2, §6). The design's `.stale` and `.resolutionFailed` are one case: the UI treats them the same, and `BookmarkedFolder` reports both as `bookmarkUnresolvable`.
public enum FolderState: Equatable, Sendable {
    case none
    case valid(displayPath: String)
    case lost(errorText: String)

    public var isLost: Bool {
        if case .lost = self { true } else { false }
    }
}

/// What a saved run error is about (design §4, "Classify error strings"). Matches the strings `ExportRunner` writes.
public enum RunErrorKind: Equatable, Sendable {
    case noFolder
    case folderLost
    case storageFull
    case read
    case dailyValues
    case other

    static let diskFullPhrases = ["isn’t enough space", "isn't enough space", "not enough space", "disk is full", "out of space"]

    public init(error: String) {
        let lowered = error.lowercased()
        if error == "no folder picked" {
            self = .noFolder
        } else if error.contains("bookmarkUnresolvable") {
            self = .folderLost
        } else if error.contains("[NSCocoaErrorDomain 640]") || error.contains("NSFileWriteOutOfSpaceError") || Self.diskFullPhrases.contains(where: { lowered.contains($0) }) {
            self = .storageFull
        } else if error.hasPrefix("read:") || error.hasPrefix("verify") || error.hasPrefix(RunRecord.observerAcknowledgementErrorPrefix) {
            self = .read
        } else if error.hasPrefix("daily values") {
            self = .dailyValues
        } else {
            self = .other
        }
    }

    var isExportError: Bool {
        switch self {
        case .noFolder, .folderLost, .storageFull, .other: true
        case .read, .dailyValues: false
        }
    }
}

/// The History row status (design §4 outcome table). Shapes stay distinct without color.
public enum RunRowOutcome: Equatable, Sendable {
    case success
    case locked
    case notRequested
    case attention
    case exportError

    public init(run: RunRecord) {
        let kinds = run.errors.map(RunErrorKind.init(error:))
        if run.daysFailed > 0 || kinds.contains(where: \.isExportError) {
            self = .exportError
        } else if run.readOutcome == ReadOutcome.failed.rawValue || kinds.contains(.read) || kinds.contains(.dailyValues) {
            self = .attention
        } else if run.readOutcome == ReadOutcome.skippedLocked.rawValue {
            self = .locked
        } else if run.readOutcome == ReadOutcome.notRequested.rawValue {
            self = .notRequested
        } else {
            self = .success
        }
    }

    public var symbolName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .locked: "lock.fill"
        case .notRequested: "minus.circle"
        case .attention: "exclamationmark.triangle.fill"
        case .exportError: "xmark.octagon.fill"
        }
    }
}

/// The Run detail recovery (design §4 recovery table). Missing health permission is never inferred from a run.
public enum RunRecovery: Equatable, Sendable {
    case pickFolder
    case pickFolderAgain
    case freeUpSpace
    case retryNextRun
    case none

    public init(run: RunRecord, folder: FolderState) {
        let kinds = Set(run.errors.map(RunErrorKind.init(error:)))
        let hasFolderError = kinds.contains(.folderLost) || kinds.contains(.noFolder)
        if folder.isLost && (hasFolderError || run.daysFailed > 0) {
            self = .pickFolderAgain
        } else if kinds.contains(.noFolder) && folder == .none {
            self = .pickFolder
        } else if kinds.contains(.storageFull) {
            self = .freeUpSpace
        } else if !run.errors.isEmpty || run.daysFailed > 0 {
            self = .retryNextRun
        } else {
            self = .none
        }
    }
}

public enum RunLabels {
    /// Design §4 trigger map, plus "App event" (this plan's label for a row no run produced). An unknown stored name is shown as saved.
    public static func trigger(_ stored: String) -> String {
        // Not a `Trigger`: the label of a history row no run produced (Task 3A).
        if stored == RunRecord.appEventTrigger { return "App event" }
        return switch Trigger(rawValue: stored) {
        case .observerWake: "Observer wake"
        case .appOpen: "App open"
        case .backgroundRefresh: "Background refresh"
        case .appIntent: "Export now"
        case .rebuildAll: "Rebuild all"
        case nil: stored
        }
    }

    /// Design §4 read-outcome map.
    public static func readOutcome(_ stored: String) -> String {
        switch ReadOutcome(rawValue: stored) {
        case .read: "Read"
        case .skippedLocked: "Skipped: locked"
        case .notRequested: "Not requested"
        case .failed: "Failed"
        case nil: stored
        }
    }

    public static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    public static func dayCounts(_ run: RunRecord) -> String {
        let counts = "\(run.daysWritten) written · \(run.daysFailed) failed"
        return run.daysPending > 0 ? "\(counts) · \(run.daysPending) pending" : counts
    }

    /// What the Export now App Intent says back to Shortcuts.
    public static func exportNowDialog(_ outcome: RunOutcome) -> String {
        var text = "\(days(outcome.daysWritten)) written, \(outcome.daysFailed) failed"
        if outcome.daysPending > 0 { text += ", \(outcome.daysPending) pending" }
        text += "."
        if let firstError = outcome.errors.first { text += " \(firstError)" }
        return text
    }
}
