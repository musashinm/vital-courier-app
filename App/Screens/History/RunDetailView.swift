import SwiftUI
import VitalCourierCore

struct RunDetailView: View {
  @Environment(AppModel.self) private var model
  let run: RunRecord
  @State private var isPickerPresented = false
  /// The save state is app-wide, so it shows here only after this screen's own picker returned a result.
  @State private var hasPickedFolderHere = false

  var body: some View {
    let formatter = StatusDateFormatter()
    let recovery = RunRecovery(run: run, folder: model.folderState)
    List {
      Section {
        DetailRow(label: "Trigger", value: RunLabels.trigger(run.trigger))
        DetailRow(label: "Time", value: formatter.fullMoment(run.startedAt))
      } header: {
        Text("Summary").foregroundStyle(Color.vcTertiaryText)
      }
      Section {
        DetailRow(label: "Read", value: RunLabels.readOutcome(run.readOutcome))
      }
      Section {
        DetailRow(label: "Days written", value: "\(run.daysWritten)")
        DetailRow(label: "Days failed", value: "\(run.daysFailed)")
        DetailRow(label: "Days pending", value: "\(run.daysPending)")
      } header: {
        Text("Files").foregroundStyle(Color.vcTertiaryText)
      }
      Section {
        if run.errors.isEmpty {
          SymbolTextRow {
            SymbolImage("checkmark.circle.fill", size: SymbolSize.status, color: .vcSuccess)
              .accessibilityHidden(true)
            Text("No errors").foregroundStyle(Color.vcPrimaryText)
          }
          .accessibilityElement(children: .combine)
        } else {
          ForEach(Array(run.errors.enumerated()), id: \.offset) { entry in
            ErrorTextView(text: entry.element)
          }
        }
      } header: {
        Text("Errors").foregroundStyle(Color.vcTertiaryText)
      }
      RecoverySection(recovery: recovery, outcome: RunRowOutcome(run: run), onPickFolder: { isPickerPresented = true })
      if hasPickedFolderHere && model.folderSave != .idle {
        Section {
          switch model.folderSave {
          case .idle: EmptyView()
          case .saving: ProgressView()
          case .saved(let displayPath): Text(FolderPathText.localized(displayPath)).foregroundStyle(Color.vcPrimaryText)
          case .failed(let errorText):
            Text("Folder couldn’t be saved").font(.headline).foregroundStyle(Color.vcPrimaryText)
            ErrorTextView(text: errorText)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(RunLabels.trigger(run.trigger))
    .navigationBarTitleDisplayMode(.inline)
    .folderPicker(
      isPresented: $isPickerPresented,
      onPick: {
        hasPickedFolderHere = true
        model.pickFolder($0)
      },
      onError: {
        hasPickedFolderHere = true
        model.folderSave = .failed(errorText: $0)
      })
  }
}

/// Design §4 run-detail recovery table. No generic "View details" and no guessed permission problem.
private struct RecoverySection: View {
  let recovery: RunRecovery
  let outcome: RunRowOutcome
  let onPickFolder: () -> Void

  var body: some View {
    switch recovery {
    case .none:
      EmptyView()
    case .pickFolder:
      Section {
        header(symbol: "folder.badge.questionmark", color: .vcWarning, text: "No folder is picked.")
        Button("Pick a folder", action: onPickFolder)
      }
    case .pickFolderAgain:
      Section {
        header(symbol: "folder.badge.minus", color: .vcError, text: "The export folder can’t be reached.")
        Button("Pick folder again", action: onPickFolder)
      }
    case .freeUpSpace:
      Section {
        header(symbol: "xmark.octagon.fill", color: .vcError, text: "Free up space, then open Vital Courier to retry.")
      }
    case .retryNextRun:
      Section {
        header(symbol: outcome.symbolName, color: outcome.color, text: "Vital Courier will try again on the next run.")
      }
    }
  }

  private func header(symbol: String, color: Color, text: LocalizedStringKey) -> some View {
    SymbolTextRow {
      SymbolImage(symbol, size: SymbolSize.status, color: color)
        .accessibilityHidden(true)
      Text(text).foregroundStyle(Color.vcPrimaryText)
    }
    .accessibilityElement(children: .combine)
  }
}
