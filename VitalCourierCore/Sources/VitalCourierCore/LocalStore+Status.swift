import Foundation
import GRDB

/// Everything Home needs, read in one transaction (design iOS App v2, §6 UI status derivation). Read-only: nothing here changes export behaviour.
public struct StoreStatusSnapshot: Equatable, Sendable {
  /// The newest row a run produced. App event rows (`RunRecord.appEventTrigger`) are skipped: they checked nothing.
  public var latestRun: RunRecord?
  /// The newest history row overall, when it is an App event row; nil when a run row is newer. Home reads it only to keep showing a saved protection failure (`HomeInputs.latestAppEvent`, Task 5).
  public var latestAppEvent: RunRecord?
  public var lastSuccessfulReadAt: Date?
  public var dailyValuesFailureStreakStart: Date?
  public var latestDailyValueDays: [HealthType: DayKey]
  /// The source of the newest sleep daily value, for "Updated today · Apple Watch".
  public var latestSleepSource: String?
  /// The newest day with a logged flow, and that flow (Cycle Tracking Spec, UI). Read whatever the switch says; Home shows them only while it is on.
  public var latestFlowDay: DayKey?
  public var latestFlow: String?
  /// The newest day with spotting logged.
  public var latestSpottingDay: DayKey?
  /// The `sample` table has any row, for any type (enabled or not, cycle types included). Current store state, not an "ever seen" marker: Clear local copy makes it false again.
  public var hasStoredHealthValue: Bool

  public init(
    latestRun: RunRecord?, latestAppEvent: RunRecord? = nil, lastSuccessfulReadAt: Date?,
    dailyValuesFailureStreakStart: Date?, latestDailyValueDays: [HealthType: DayKey], latestSleepSource: String?,
    latestFlowDay: DayKey? = nil, latestFlow: String? = nil, latestSpottingDay: DayKey? = nil,
    hasStoredHealthValue: Bool = true
  ) {
    self.latestRun = latestRun
    self.latestAppEvent = latestAppEvent
    self.lastSuccessfulReadAt = lastSuccessfulReadAt
    self.dailyValuesFailureStreakStart = dailyValuesFailureStreakStart
    self.latestDailyValueDays = latestDailyValueDays
    self.latestSleepSource = latestSleepSource
    self.latestFlowDay = latestFlowDay
    self.latestFlow = latestFlow
    self.latestSpottingDay = latestSpottingDay
    self.hasStoredHealthValue = hasStoredHealthValue
  }
}

extension LocalStore {
  public func statusSnapshot() throws -> StoreStatusSnapshot {
    try dbQueue.read { db in
      let newestRow = try Self.runs(db, before: nil, limit: 1).first
      // Cycle days have no `dailyValue` rows, so their recency comes from `cycleDailyValue`.
      let latestFlowRow = try Row.fetchOne(
        db, sql: "SELECT day, flow FROM cycleDailyValue WHERE flow IS NOT NULL ORDER BY day DESC LIMIT 1")
      let latestFlowDay = try latestFlowRow.map { row in try Self.cycleDayKey(row["day"]) }
      let latestFlow: String? = latestFlowRow?["flow"]
      let latestSpottingDay = try String.fetchOne(
        db, sql: "SELECT day FROM cycleDailyValue WHERE spotting = 1 ORDER BY day DESC LIMIT 1"
      ).map(Self.cycleDayKey)
      return StoreStatusSnapshot(
        latestRun: try Self.latestRunSkippingAppEvents(db),
        latestAppEvent: newestRow?.trigger == RunRecord.appEventTrigger ? newestRow : nil,
        lastSuccessfulReadAt: try Self.lastSuccessfulReadAt(db),
        dailyValuesFailureStreakStart: try Self.dailyValuesFailureStreakStart(db),
        latestDailyValueDays: try Self.latestDailyValueDays(db),
        latestSleepSource: try String.fetchOne(
          db,
          sql: "SELECT source FROM dailyValue WHERE type = ? ORDER BY day DESC LIMIT 1",
          arguments: [HealthType.sleep.rawValue]
        ),
        latestFlowDay: latestFlowDay,
        latestFlow: latestFlow,
        latestSpottingDay: latestSpottingDay,
        hasStoredHealthValue: try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM sample)") ?? false
      )
    }
  }

  static func cycleDayKey(_ text: String) throws -> DayKey {
    guard let day = DayKey(text) else { throw LocalStoreError.corruptRow("cycleDailyValue \(text)") }
    return day
  }

  /// Newest first. Pass the last record of the previous page as `cursor`; new runs arriving meanwhile never shift or repeat rows.
  public func runs(before cursor: RunRecord?, limit: Int) throws -> [RunRecord] {
    try dbQueue.read { db in try Self.runs(db, before: cursor, limit: limit) }
  }

  public func lastSuccessfulReadAt() throws -> Date? {
    try dbQueue.read { db in try Self.lastSuccessfulReadAt(db) }
  }

  /// The newest day with a stored daily value, per type. Sleep uses its wake day.
  public func latestDailyValueDays() throws -> [HealthType: DayKey] {
    try dbQueue.read { db in try Self.latestDailyValueDays(db) }
  }

  /// Start of the current run of daily-values failures: readable runs (read or failed) newest first; a run with a `daily values` error extends the streak, the first one without ends it. Locked and not-requested runs are skipped.
  public func dailyValuesFailureStreakStart() throws -> Date? {
    try dbQueue.read { db in try Self.dailyValuesFailureStreakStart(db) }
  }

  /// Every sleep source seen locally, for the Settings sleep-source list. Names are never normalized.
  public func sleepSourceNames() throws -> [String] {
    try dbQueue.read { db in
      try String.fetchAll(
        db, sql: "SELECT DISTINCT source FROM sample WHERE type = ?", arguments: [HealthType.sleep.rawValue])
    }
    .sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
  }

  static func latestRunSkippingAppEvents(_ db: Database) throws -> RunRecord? {
    try Row.fetchOne(
      db, sql: "SELECT * FROM runRecord WHERE triggerName <> ? ORDER BY startedAt DESC, id DESC LIMIT 1",
      arguments: [RunRecord.appEventTrigger]
    ).map(runRecord(from:))
  }

  static func runs(_ db: Database, before cursor: RunRecord?, limit: Int) throws -> [RunRecord] {
    let rows: [Row]
    if let cursor {
      guard let cursorID = cursor.id else { throw LocalStoreError.invalidCursor }
      let cursorStart = cursor.startedAt.timeIntervalSince1970
      rows = try Row.fetchAll(
        db,
        sql: """
          SELECT * FROM runRecord
          WHERE startedAt < ? OR (startedAt = ? AND id < ?)
          ORDER BY startedAt DESC, id DESC LIMIT ?
          """, arguments: [cursorStart, cursorStart, cursorID, limit])
    } else {
      rows = try Row.fetchAll(
        db, sql: "SELECT * FROM runRecord ORDER BY startedAt DESC, id DESC LIMIT ?", arguments: [limit])
    }
    return try rows.map(runRecord(from:))
  }

  static func lastSuccessfulReadAt(_ db: Database) throws -> Date? {
    try Double.fetchOne(
      db,
      sql: "SELECT MAX(startedAt) FROM runRecord WHERE readOutcome = ?",
      arguments: [ReadOutcome.read.rawValue]
    ).map { Date(timeIntervalSince1970: $0) }
  }

  static func latestDailyValueDays(_ db: Database) throws -> [HealthType: DayKey] {
    var days: [HealthType: DayKey] = [:]
    for row in try Row.fetchAll(db, sql: "SELECT type, MAX(day) AS latestDay FROM dailyValue GROUP BY type") {
      let typeRaw: String = row["type"]
      let dayText: String = row["latestDay"]
      guard let type = HealthType(rawValue: typeRaw), let day = DayKey(dayText) else {
        throw LocalStoreError.corruptRow("dailyValue \(typeRaw) \(dayText)")
      }
      days[type] = day
    }
    return days
  }

  static func dailyValuesFailureStreakStart(_ db: Database) throws -> Date? {
    let rows = try Row.fetchAll(
      db,
      sql: "SELECT * FROM runRecord WHERE readOutcome IN (?, ?) ORDER BY startedAt DESC, id DESC",
      arguments: [ReadOutcome.read.rawValue, ReadOutcome.failed.rawValue]
    )
    var streakStart: Date?
    for row in rows {
      let run = try runRecord(from: row)
      guard run.errors.contains(where: { $0.hasPrefix("daily values") }) else { break }
      streakStart = run.startedAt
    }
    return streakStart
  }
}
