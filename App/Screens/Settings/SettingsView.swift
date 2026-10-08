import SwiftUI
import VitalCourierCore

enum AppLinks {
    /// Design open question 1. If the final route differs, change the URL, not the label.
    static let privacyPolicy = URL(string: "https://vitalcourier.app/privacy")
    static let sourceCode = URL(string: "https://github.com/musashinm/vital-courier-app")
    /// Design open question 2: hidden while the repository is private.
    static let showsSourceCode = false

    static var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(shortVersion) (\(build))"
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isPickerPresented = false
    @State private var confirmsRebuild = false
    @State private var confirmsClear = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SleepSourceView()
                } label: {
                    DetailRow(label: "Sleep source", value: model.sleepSources.selectedDisplayName)
                }
            } header: {
                Text("Sleep").foregroundStyle(Color.vcTertiaryText)
            } footer: {
                Text(SleepSourceView.footer).foregroundStyle(Color.vcTertiaryText)
            }

            Section {
                folderRow
                if case .lost(let errorText) = model.folderState {
                    ErrorTextView(text: errorText)
                }
                switch model.folderSave {
                case .idle, .saved: EmptyView()
                case .saving:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Saving folder…").foregroundStyle(Color.vcSecondaryText)
                    }
                case .failed(let errorText):
                    Text("Folder couldn’t be saved").font(.headline).foregroundStyle(Color.vcPrimaryText)
                    ErrorTextView(text: errorText)
                }
            } header: {
                Text("Export folder").foregroundStyle(Color.vcTertiaryText)
            } footer: {
                Text("Vital Courier writes inside a subfolder named Vital Courier. Edits there can be replaced.")
                    .foregroundStyle(Color.vcTertiaryText)
            }

            Section {
                rebuildRow
                if let rebuildError = model.rebuildError {
                    ErrorTextView(text: rebuildError)
                }
                clearRow
                if let clearError = model.clearError {
                    HStack(spacing: 12) {
                        SymbolImage("exclamationmark.circle.fill", size: SymbolSize.status, color: .vcError)
                            .accessibilityHidden(true)
                        Text("Local copy couldn’t be cleared").font(.headline).foregroundStyle(Color.vcPrimaryText)
                    }
                    .accessibilityElement(children: .combine)
                    ErrorTextView(text: clearError)
                }
            } header: {
                Text("Maintenance").foregroundStyle(Color.vcTertiaryText)
            }

            Section {
                if let privacyPolicy = AppLinks.privacyPolicy {
                    Link(destination: privacyPolicy) {
                        LinkRow(title: "Privacy policy")
                    }
                }
                if AppLinks.showsSourceCode, let sourceCode = AppLinks.sourceCode {
                    Link(destination: sourceCode) {
                        LinkRow(title: "Source code")
                    }
                }
                DetailRow(label: "Version", value: AppLinks.versionText)
            } header: {
                Text("Privacy and app").foregroundStyle(Color.vcTertiaryText)
            }

            #if DEBUG
            Section {
                NavigationLink("Diagnostics") { DiagnosticsView() }
            } header: {
                Text("Debug").foregroundStyle(Color.vcTertiaryText)
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .task { await model.sleepSources.load() }
        .alert("Clear the local copy?", isPresented: $confirmsClear) {
            Button("Clear local copy", role: .destructive) { model.clearLocalCopy() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Vital Courier’s protected local health-data database. It does not delete Apple Health data or exported files. Run history, settings, and your folder choice remain. The next unlocked run rereads the four data types.")
        }
        .folderPicker(isPresented: $isPickerPresented, onPick: { model.pickFolder($0) }, onError: { model.folderSave = .failed(errorText: $0) })
    }

    private var folderRow: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 12) {
                SymbolImage(model.folderState.isLost ? "folder.badge.minus" : "folder.fill", size: SymbolSize.row, color: model.folderState.isLost ? .vcError : .vcSecondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder").foregroundStyle(Color.vcPrimaryText)
                    switch model.folderState {
                    case .none:
                        Text("Pick a folder").font(.subheadline).foregroundStyle(Color.vcAccent)
                    case .valid(let displayPath):
                        Text(FolderPathText.localized(displayPath)).font(.subheadline).foregroundStyle(Color.vcSecondaryText)
                    case .lost:
                        Text("Pick again").font(.subheadline).foregroundStyle(Color.vcError)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.vcTertiaryText)
            }
            .frame(minHeight: 56)
        }
        .disabled(model.folderSave == .saving)
    }

    private var rebuildTitle: LocalizedStringKey {
        model.maintenance == .rebuilding ? "Rebuilding…" : "Rebuild all"
    }

    private var clearTitle: LocalizedStringKey {
        model.maintenance == .clearing ? "Clearing…" : "Clear local copy"
    }

    private var rebuildRow: some View {
        Button {
            confirmsRebuild = true
        } label: {
            HStack(spacing: 12) {
                SymbolImage("arrow.clockwise.circle", size: SymbolSize.row, color: .vcAccent)
                    .accessibilityHidden(true)
                Text(rebuildTitle).foregroundStyle(Color.vcPrimaryText)
                Spacer()
                if model.maintenance == .rebuilding { ProgressView() }
            }
            .frame(minHeight: 44)
        }
        // Disabled while rebuilding and while clearing (round-4 nit, boards 28 and 30).
        .disabled(model.maintenance != .idle)
        // On the row, not the List: where iOS shows this dialog as a popover (regular width, and iPhone too on iOS 26), it points at the view it's attached to.
        .confirmationDialog("Rebuild every export?", isPresented: $confirmsRebuild, titleVisibility: .visible) {
            Button("Rebuild all") { model.rebuildAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Vital Courier will reread all four data types and rewrite every day and month it knows about. Keep this iPhone unlocked. This can take a while.")
        }
    }

    private var clearRow: some View {
        Button {
            confirmsClear = true
        } label: {
            HStack(spacing: 12) {
                SymbolImage("trash", size: SymbolSize.row, color: .vcError)
                    .accessibilityHidden(true)
                Text(clearTitle).foregroundStyle(Color.vcError)
                Spacer()
                if model.maintenance == .clearing { ProgressView() }
            }
            .frame(minHeight: 44)
        }
        .disabled(model.maintenance != .idle)
    }
}

private struct LinkRow: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            SymbolImage("arrow.up.forward.square", size: SymbolSize.row, color: .vcAccent)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(Color.vcAccent)
        }
        .frame(minHeight: 44)
    }
}
