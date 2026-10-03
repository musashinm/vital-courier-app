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

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Replaces the list with the newest page. Loaded rows stay on screen until the new page arrives.
    func reload() async {
        await load(after: nil)
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd, let last = runs.last else { return }
        await load(after: last)
    }

    private func load(after cursor: RunRecord?) async {
        isLoading = true
        let environment = self.environment
        let limit = Self.pageSize
        do {
            let page = try await Task.detached {
                try environment.readyStore().runs(before: cursor, limit: limit)
            }.value
            runs = cursor == nil ? page : runs + page
            reachedEnd = page.count < limit
            loadError = nil
        } catch {
            // Keep the rows already loaded (design §4, History load error).
            loadError = String(describing: error)
        }
        hasLoadedOnce = true
        isLoading = false
    }
}
