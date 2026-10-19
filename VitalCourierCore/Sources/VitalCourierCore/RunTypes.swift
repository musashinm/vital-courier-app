import Foundation

public enum Trigger: String, Sendable, CaseIterable {
  case observerWake
  case appOpen
  case backgroundRefresh
  case appIntent
  case rebuildAll
}

public enum VerifyScope: Int, Comparable, Sendable {
  case none
  case last30Days
  case allDates

  public static func < (lhs: VerifyScope, rhs: VerifyScope) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct RunOptions: Equatable, Sendable {
  public var read: Bool
  public var verify: VerifyScope
  public var markAllDirty: Bool

  public init(read: Bool, verify: VerifyScope, markAllDirty: Bool) {
    self.read = read
    self.verify = verify
    self.markAllDirty = markAllDirty
  }

  /// Spec, Data flow, Triggers table. Reading always also needs HealthKit to be readable.
  public static func forTrigger(_ trigger: Trigger) -> RunOptions {
    switch trigger {
    case .observerWake: RunOptions(read: true, verify: .none, markAllDirty: false)
    case .appOpen, .backgroundRefresh: RunOptions(read: true, verify: .last30Days, markAllDirty: false)
    case .appIntent: RunOptions(read: false, verify: .none, markAllDirty: false)
    case .rebuildAll: RunOptions(read: true, verify: .allDates, markAllDirty: true)
    }
  }

  public func merged(with other: RunOptions) -> RunOptions {
    RunOptions(
      read: read || other.read, verify: max(verify, other.verify), markAllDirty: markAllDirty || other.markAllDirty)
  }
}

public enum ReadOutcome: String, Sendable {
  case read
  case skippedLocked = "skipped: locked"
  case notRequested = "not requested"
  case failed
}

public struct RunOutcome: Equatable, Sendable {
  public var readOutcome: ReadOutcome
  public var daysWritten: Int
  public var daysFailed: Int
  /// Days left dirty without a failure: stale values, no folder, or a cancelled run.
  public var daysPending: Int
  public var errors: [String]

  public init(readOutcome: ReadOutcome, daysWritten: Int, daysFailed: Int, daysPending: Int, errors: [String]) {
    self.readOutcome = readOutcome
    self.daysWritten = daysWritten
    self.daysFailed = daysFailed
    self.daysPending = daysPending
    self.errors = errors
  }
}
