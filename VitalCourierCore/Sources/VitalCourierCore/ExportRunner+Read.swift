import Foundation

extension ExportRunner {
  func readStep(types: [HealthType], zone: TimeZone, changedTypes: inout Set<HealthType>, errors: inout [String]) async
    -> ReadOutcome
  {
    do {
      for type in types {
        var hasMore = true
        while hasMore {
          if Task.isCancelled { return .read }
          let anchor = try store.anchor(for: type)
          let changes = try await health.changes(for: type, since: anchor)
          if changes.hasMore && (changes.newAnchor == nil || changes.newAnchor == anchor) {
            throw HealthSourceError.anchorDidNotAdvance(type)
          }
          // Each batch commits with its anchor (spec, Data flow 1.2), so an expired run keeps what it read.
          try store.applyChanges(changes, for: type, fallbackTimeZone: zone)
          if !changes.added.isEmpty || !changes.deletedUUIDs.isEmpty { changedTypes.insert(type) }
          hasMore = changes.hasMore
        }
      }
      return .read
    } catch HealthSourceError.readRefused {
      return .skippedLocked
    } catch {
      errors.append("read: \(error)")
      return .failed
    }
  }
}
