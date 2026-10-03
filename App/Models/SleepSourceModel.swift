import Foundation
import Observation
import VitalCourierCore

/// Settings → Sleep source (design §5). nil means Automatic.
@MainActor @Observable
final class SleepSourceModel {
    let environment: AppEnvironment
    var names: [String] = []
    var selected: String?
    var isSaving = false
    var saveError: String?
    var loadError: String?
    /// Called after a choice is saved, to start a run that rewrites the affected notes.
    var onSaved: () -> Void = {}
    /// Bumped by every accepted choice. A load that started before a choice must not overwrite it.
    private var choiceGeneration = 0

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var selectedDisplayName: String {
        selected ?? "Automatic"
    }

    func load() async {
        let environment = self.environment
        let generation = choiceGeneration
        do {
            let (sourceNames, preference) = try await Task.detached {
                let store = try environment.readyStore()
                return (try store.sleepSourceNames(), try store.sleepSourcePreference())
            }.value
            // A saved choice stays listed even after Clear local copy removed its samples.
            let appliesPreference = generation == choiceGeneration && !isSaving
            let listedChoice = appliesPreference ? preference : selected
            names = Self.listing(sourceNames, including: listedChoice)
            if appliesPreference { selected = preference }
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    private static func listing(_ names: [String], including choice: String?) -> [String] {
        guard let choice, !names.contains(choice) else { return names }
        return (names + [choice]).sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The checkmark moves at once; on failure it moves back and the real error shows.
    func choose(_ choice: String?) {
        guard choice != selected, !isSaving else { return }
        let previous = selected
        choiceGeneration += 1
        selected = choice
        isSaving = true
        saveError = nil
        let environment = self.environment
        Task {
            do {
                try await Task.detached {
                    let store = try environment.readyStore()
                    try store.setSleepSourcePreference(choice)
                    // The write protected the files (Task 3A); a failure there is saved to run history.
                    environment.recordProtectionFailures(in: store)
                }.value
                isSaving = false
                onSaved()
            } catch {
                selected = previous
                names = Self.listing(names, including: previous)
                isSaving = false
                saveError = String(describing: error)
            }
        }
    }
}
