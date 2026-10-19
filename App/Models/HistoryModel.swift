import Foundation
import Observation
import VitalCourierCore

/// Run history, newest first, 50 rows at a time (design §4 and open question 3).
@MainActor @Observable
final class HistoryModel {
  static let pageSize = 50

  let environment: AppEnvironment
  var runs: [RunRecord] = []
  var isLoading = false
  var loadError: String?
  var hasLoadedOnce = false
  var reachedEnd = false
  /// Bumped by every reload. A page request that started before a reload is stale and is dropped.
  private var reloadGeneration = 0

  init(environment: AppEnvironment) {
    self.environment = environment
  }

  /// Replaces the list with the newest page. Loaded rows stay on screen until the new page arrives.
  func reload() async {
    reloadGeneration += 1
    await load(after: nil)
  }

  func loadMore() async {
    guard !isLoading, !reachedEnd, let last = runs.last else { return }
    await load(after: last)
  }

  private func load(after cursor: RunRecord?) async {
    isLoading = true
    let generation = reloadGeneration
    let environment = self.environment
    let limit = Self.pageSize
    do {
      let page = try await Task.detached {
        try environment.readyStore().runs(before: cursor, limit: limit)
      }.value
      guard generation == reloadGeneration else { return }
      runs = cursor == nil ? page : runs + page
      reachedEnd = page.count < limit
      loadError = nil
    } catch {
      guard generation == reloadGeneration else { return }
      // Keep the rows already loaded (design §4, History load error).
      loadError = String(describing: error)
    }
    hasLoadedOnce = true
    isLoading = false
  }
}
