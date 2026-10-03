import SwiftUI
import VitalCourierCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isPickerPresented = false

    var body: some View {
        let formatter = StatusDateFormatter()
        let summary = model.homeSummary
        let today = DayKey(date: model.now, timeZone: .current)
        let setupDay = model.environment.settings.setupCompletedAt.map { DayKey(date: $0, timeZone: .current) }
        List {
            Section {
                SummaryRow(
                    summary: summary,
                    text: summary.text(formatter: formatter, now: model.now),
                    hidesPickAction: { if case .failed = model.folderSave { true } else { false } }(),
                    onPickFolder: { isPickerPresented = true },
                    onViewRecentRuns: { model.selectedTab = .history }
                )
                FolderSaveRow(state: model.folderSave, onPickFolder: { isPickerPresented = true })
                if let statusError = model.statusError {
                    ErrorTextView(text: statusError)
                }
            }
            Section {
                Text("Vital Courier runs when Apple Health reports changes and at other opportunities chosen by iOS. Reading waits until this iPhone is unlocked.")
                    .font(.body)
                    .foregroundStyle(Color.vcSecondaryText)
            } header: {
                Text("What happens next").foregroundStyle(Color.vcTertiaryText)
            }
            Section {
                ForEach(HealthType.allCases, id: \.self) { type in
                    let recency = TypeRecency.resolve(latestDay: model.snapshot?.latestDailyValueDays[type], setupDay: setupDay, today: today)
                    HealthRow(
                        type: type,
                        recency: recency,
                        valueText: recency.valueText(formatter: formatter, today: today, source: type == .sleep ? model.snapshot?.latestSleepSource : nil)
                    )
                }
            } header: {
                Text("Health data").foregroundStyle(Color.vcTertiaryText)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Vital Courier")
        .folderPicker(isPresented: $isPickerPresented, onPick: { model.pickFolder($0) }, onError: { model.folderSave = .failed(errorText: $0) })
        .onChange(of: model.isAppOpenRunActive) { _, isActive in
            // Announce the start and the result once each; never the spinner (design, Accessibility).
            let announcement = isActive ? "Checking for updates" : model.homeSummary.text(formatter: formatter, now: model.now).title
            AccessibilityNotification.Announcement(announcement).post()
        }
    }
}

private struct SummaryRow: View {
    let summary: HomeSummary
    let text: HomeSummaryText
    let hidesPickAction: Bool
    let onPickFolder: () -> Void
    let onViewRecentRuns: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The spinner is centred on the whole row; the symbol stays on the title's baseline.
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    SymbolImage(text.symbolName, size: SymbolSize.status, color: symbolColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text.title)
                            .font(.headline)
                            .foregroundStyle(Color.vcPrimaryText)
                        if let detail = text.detail {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(Color.vcSecondaryText)
                        }
                    }
                }
                if case .running = summary {
                    Spacer()
                    ProgressView()
                }
            }
            .accessibilityElement(children: .combine)
            if let errorText = text.errorText {
                ErrorTextView(text: errorText)
            }
            if text.showsMoreErrorsNote {
                Text("More errors in run details")
                    .font(.footnote)
                    .foregroundStyle(Color.vcSecondaryText)
            }
            action
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var action: some View {
        switch text.action {
        case .none:
            EmptyView()
        case .runDetails:
            if let summaryRun {
                NavigationLink("Run details") { RunDetailView(run: summaryRun) }
            }
        case .pickFolder:
            if !hidesPickAction { Button("Pick a folder", action: onPickFolder) }
        case .pickFolderAgain:
            if !hidesPickAction { Button("Pick it again", action: onPickFolder) }
        case .viewRecentRuns:
            Button("View recent runs", action: onViewRecentRuns)
        }
    }

    /// The run the summary was resolved from, including an App event row for a protection failure.
    private var summaryRun: RunRecord? {
        switch summary {
        case .protectionFailure(let run), .writeFailure(let run), .daysUpdated(let run), .upToDate(let run): run
        default: nil
        }
    }

    private var symbolColor: Color {
        switch summary {
        case .daysUpdated, .upToDate: .vcSuccess
        case .folderLost, .writeFailure, .protectionFailure, .protectionFailurePending: .vcError
        case .noFolder, .readOverdue, .dailyValuesOverdue: .vcWarning
        case .running, .awaitingReread, .waitingForFirstExport: .vcSecondaryText
        }
    }
}

/// Picking a folder from Home: progress and the real error (design §5, "Bookmark save/resolve uses the first-run loading and error states").
private struct FolderSaveRow: View {
    let state: AppModel.FolderSaveState
    let onPickFolder: () -> Void

    var body: some View {
        switch state {
        case .idle, .saved:
            EmptyView()
        case .saving:
            HStack(spacing: 8) {
                ProgressView()
                Text("Saving folder…").foregroundStyle(Color.vcSecondaryText)
            }
        case .failed(let errorText):
            VStack(alignment: .leading, spacing: 8) {
                Text("Folder couldn’t be saved").font(.headline).foregroundStyle(Color.vcPrimaryText)
                ErrorTextView(text: errorText)
                Button("Choose another folder", action: onPickFolder)
            }
        }
    }
}

private struct HealthRow: View {
    let type: HealthType
    let recency: TypeRecency
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                SymbolImage(isSilent ? "exclamationmark.circle" : type.symbolName, size: SymbolSize.row, color: isSilent ? .vcWarning : .vcSecondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.body)
                        .foregroundStyle(Color.vcPrimaryText)
                    Text(valueText)
                        .font(.subheadline)
                        .foregroundStyle(Color.vcSecondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            if isSilent {
                SilentTypeHint()
            }
        }
        .frame(minHeight: 56, alignment: .leading)
    }

    private var isSilent: Bool {
        recency == .silentForAWeek
    }
}
