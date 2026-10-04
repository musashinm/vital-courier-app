import AppIntents
import VitalCourierCore

/// "Export now" for Shortcuts (spec, Triggers): writes dirty days from saved data only, so it works while the iPhone is locked. Runs in the app process without opening the app.
struct ExportNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Export now"
    static let description = IntentDescription("Writes the health data Vital Courier has already saved to your folder. It doesn’t read new data.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await AppEnvironment.shared.request(.appIntent)
        return .result(dialog: IntentDialog(stringLiteral: RunLabels.exportNowDialog(outcome)))
    }
}

struct VitalCourierShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExportNowIntent(),
            phrases: ["Export now in \(.applicationName)"],
            shortTitle: "Export now",
            systemImageName: "square.and.arrow.up"
        )
    }
}
