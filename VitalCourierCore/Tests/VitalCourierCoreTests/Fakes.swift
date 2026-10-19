import Foundation
import Synchronization

@testable import VitalCourierCore

final class EventLog: Sendable {
  private let entries = Mutex<[String]>([])
  func append(_ entry: String) { entries.withLock { $0.append(entry) } }
  var all: [String] { entries.withLock { $0 } }
}

struct FakeWriteError: Error {}

actor FakeHealthSource: HealthSource {
  let log: EventLog
  var readable = true
  var refuseReads = false
  var queuedChanges: [HealthType: [HealthChanges]] = [:]
  var receivedAnchors: [HealthType: [Data?]] = [:]
  var cancelOnNextChanges = false
  var storedSamples: [HealthType: [HealthSample]] = [:]
  var statistics: [String: DailyStatistic] = [:]
  var failingStatistics: Set<String> = []
  var failingChangeTypes: Set<HealthType> = []
  var earliest: Date?
  var earliestRequestedTypes: [[HealthType]] = []
  var requestedSampleIntervals: [HealthType: [DateInterval]] = [:]
  var cancelOnSamplesCall: (type: HealthType, number: Int)?

  init(log: EventLog = EventLog()) { self.log = log }

  func setReadable(_ value: Bool) { readable = value }
  func setRefuseReads(_ value: Bool) { refuseReads = value }
  func queue(_ changes: HealthChanges, for type: HealthType) { queuedChanges[type, default: []].append(changes) }
  func cancelCurrentTaskOnNextChanges() { cancelOnNextChanges = true }
  /// Cancels the calling task during the given 1-based `samples` call for `type`, the way `cancelCurrentTaskOnNextChanges` does for `changes`.
  func cancelCurrentTaskOnSamplesCall(number: Int, for type: HealthType) { cancelOnSamplesCall = (type, number) }
  func setSamples(_ samples: [HealthSample], for type: HealthType) { storedSamples[type] = samples }
  func setStatistic(_ value: Double?, for type: HealthType, day: DayKey) {
    statistics["\(type.rawValue)|\(day)"] = value.map { DailyStatistic(value: $0) }
  }
  func setStatisticRange(_ statistic: DailyStatistic, for type: HealthType, day: DayKey) {
    statistics["\(type.rawValue)|\(day)"] = statistic
  }
  func failStatistic(for type: HealthType, day: DayKey) { failingStatistics.insert("\(type.rawValue)|\(day)") }
  func failChanges(for type: HealthType) { failingChangeTypes.insert(type) }
  func setEarliest(_ value: Date?) { earliest = value }

  func isReadable() -> Bool { readable }

  func changes(for type: HealthType, since anchor: Data?) throws -> HealthChanges {
    if refuseReads { throw HealthSourceError.readRefused }
    if failingChangeTypes.contains(type) { throw FakeWriteError() }
    log.append("changes \(type.rawValue)")
    receivedAnchors[type, default: []].append(anchor)
    if cancelOnNextChanges {
      cancelOnNextChanges = false
      withUnsafeCurrentTask { $0?.cancel() }
    }
    guard var batches = queuedChanges[type], !batches.isEmpty else { return HealthChanges() }
    let next = batches.removeFirst()
    queuedChanges[type] = batches
    return next
  }

  func samples(for type: HealthType, in interval: DateInterval) -> [HealthSample] {
    log.append("samples \(type.rawValue)")
    requestedSampleIntervals[type, default: []].append(interval)
    if let target = cancelOnSamplesCall, target.type == type, requestedSampleIntervals[type]?.count == target.number {
      withUnsafeCurrentTask { $0?.cancel() }
    }
    return (storedSamples[type] ?? []).filter { interval.start <= $0.start && $0.start < interval.end }
  }

  func earliestSampleDate(types: [HealthType]) -> Date? {
    earliestRequestedTypes.append(types)
    return earliest
  }

  func dailyStatistic(for type: HealthType, day: DayKey, timeZone: TimeZone) throws -> DailyStatistic? {
    let key = "\(type.rawValue)|\(day)"
    log.append("statistic \(key)")
    if failingStatistics.contains(key) { throw FakeWriteError() }
    return statistics[key]
  }
}

final class FakeDestination: ExportDestination {
  private struct State {
    var files: [String: Data] = [:]
    var writeCounts: [String: Int] = [:]
    var failingPaths: Set<String> = []
    var cancelCurrentTaskOnFirstWriteTo: String?
    var onFirstWrite: (@Sendable () -> Void)?
  }

  private let state = Mutex(State())

  func failWrites(to path: String) { state.withLock { $0.failingPaths.insert(path) } }
  func cancelCurrentTaskOnFirstWrite(to path: String) { state.withLock { $0.cancelCurrentTaskOnFirstWriteTo = path } }
  func runOnFirstWrite(_ action: @escaping @Sendable () -> Void) { state.withLock { $0.onFirstWrite = action } }
  var paths: Set<String> { state.withLock { Set($0.files.keys) } }
  func text(at path: String) -> String? {
    // swiftlint:disable:next optional_data_string_conversion - test fake; lossy decoding of the written bytes is fine
    state.withLock { $0.files[path] }.map { String(decoding: $0, as: UTF8.self) }
  }
  func writeCount(at path: String) -> Int { state.withLock { $0.writeCounts[path] ?? 0 } }

  func write(_ data: Data, to relativePath: String) throws {
    let hook = state.withLock { current -> (@Sendable () -> Void)? in
      let action = current.onFirstWrite
      current.onFirstWrite = nil
      return action
    }
    hook?()
    let shouldCancel = try state.withLock { current -> Bool in
      if current.failingPaths.contains(relativePath) { throw FakeWriteError() }
      current.files[relativePath] = data
      current.writeCounts[relativePath, default: 0] += 1
      let cancel = current.cancelCurrentTaskOnFirstWriteTo == relativePath
      if cancel { current.cancelCurrentTaskOnFirstWriteTo = nil }
      return cancel
    }
    if shouldCancel { withUnsafeCurrentTask { $0?.cancel() } }
  }
}
