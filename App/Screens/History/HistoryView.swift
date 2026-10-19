import SwiftUI
import VitalCourierCore

struct HistoryView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let history = model.history
    let formatter = StatusDateFormatter()
    Group {
      if history.runs.isEmpty && history.hasLoadedOnce && history.loadError == nil {
        ContentUnavailableView {
          Label("No runs yet", systemImage: "clock.arrow.circlepath")
        } description: {
          Text("Runs will appear after setup finishes.")
        }
      } else {
        List {
          if let loadError = history.loadError {
            Section {
              VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                  SymbolImage("clock.badge.exclamationmark.fill", size: SymbolSize.status, color: .vcError)
                    .accessibilityHidden(true)
                  Text("History couldn’t be loaded").font(.headline).foregroundStyle(Color.vcPrimaryText)
                }
                .accessibilityElement(children: .combine)
                ErrorTextView(text: loadError)
                Button("Try again") {
                  Task { await history.reload() }
                }
              }
            }
          }
          let groups = RunMonthGroup.groups(history.runs, timeZone: formatter.timeZone)
          ForEach(groups) { group in
            Section {
              ForEach(group.runs, id: \.id) { run in
                NavigationLink {
                  RunDetailView(run: run)
                } label: {
                  RunRow(run: run, formatter: formatter, now: model.now)
                }
                .onAppear {
                  if run.id == history.runs.last?.id {
                    Task { await history.loadMore() }
                  }
                }
              }
            } header: {
              if groups.count > 1 {
                Text(formatter.monthTitle(group.month)).foregroundStyle(Color.vcTertiaryText)
              }
            }
          }
          if history.isLoading && !history.runs.isEmpty {
            ProgressView().frame(maxWidth: .infinity)
          }
        }
        .listStyle(.insetGrouped)
      }
    }
    .navigationTitle("History")
    .task {
      if !history.hasLoadedOnce { await history.reload() }
    }
  }
}

private struct RunRow: View {
  let run: RunRecord
  let formatter: StatusDateFormatter
  let now: Date

  var body: some View {
    let outcome = RunRowOutcome(run: run)
    HStack(alignment: .center, spacing: 12) {
      SymbolImage(outcome.symbolName, size: SymbolSize.status, color: outcome.color)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(RunLabels.trigger(run.trigger))
          .font(.headline)
          .foregroundStyle(Color.vcPrimaryText)
        Text(formatter.capitalizedFirst(formatter.moment(run.startedAt, now: now)))
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(Color.vcSecondaryText)
        Text(RunLabels.readOutcome(run.readOutcome))
          .font(.subheadline)
          .foregroundStyle(Color.vcSecondaryText)
        Text(RunLabels.dayCounts(run))
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(Color.vcSecondaryText)
      }
    }
    .frame(minHeight: 56, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
