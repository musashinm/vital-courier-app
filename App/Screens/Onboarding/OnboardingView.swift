import SwiftUI

/// Design §2: the two prerequisite steps. No Skip, no custom permission toggles.
struct OnboardingView: View {
    private enum Step {
        case health
        case folder
    }

    @State private var step = Step.health

    var body: some View {
        switch step {
        case .health: HealthPermissionStep { step = .folder }
        case .folder: FolderStep()
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
        .background(Color.vcAppBackground)
    }
}

private struct FactRow: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            SymbolImage(symbol, size: SymbolSize.row, color: .vcSecondaryText)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.vcPrimaryText)
        }
    }
}

private struct HealthPermissionStep: View {
    @Environment(AppModel.self) private var model
    let onDone: () -> Void
    @State private var isRequesting = false
    @State private var requestError: String?

    private var continueTitle: LocalizedStringKey {
        requestError == nil ? "Continue" : "Try again"
    }

    var body: some View {
        OnboardingPage {
            SymbolImage("heart.fill", size: SymbolSize.hero, color: .vcAccent)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Apple Health data")
            Text("Your health data, in your folder.")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.vcPrimaryText)
            Text("Vital Courier reads steps, exercise minutes, resting heart rate, sleep, and weight from the Apple Health app. It sends nothing to an account or server.")
                .font(.body)
                .foregroundStyle(Color.vcSecondaryText)
            VStack(alignment: .leading, spacing: 16) {
                FactRow(symbol: "heart.fill", text: "Five data types")
                FactRow(symbol: "doc.text.fill", text: "JSON and daily Markdown")
                FactRow(symbol: "folder.fill", text: "A folder you choose in Files")
            }
            Text("Vital Courier keeps a protected local working copy so exports can finish in the background. You can clear it in Settings.")
                .font(.footnote)
                .foregroundStyle(Color.vcTertiaryText)
            if let requestError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        SymbolImage("heart.slash.fill", size: SymbolSize.status, color: .vcError)
                            .accessibilityHidden(true)
                        Text("Health access couldn’t be requested")
                            .font(.headline)
                            .foregroundStyle(Color.vcPrimaryText)
                    }
                    .accessibilityElement(children: .combine)
                    ErrorTextView(text: requestError)
                }
            }
            if isRequesting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for Apple Health…").foregroundStyle(Color.vcSecondaryText)
                }
            }
            Button(continueTitle, action: request)
                .buttonStyle(ProminentActionStyle())
                .disabled(isRequesting)
        }
    }

    private func request() {
        isRequesting = true
        requestError = nil
        Task {
            do {
                try await model.requestHealthAuthorization()
                isRequesting = false
                onDone()
            } catch {
                isRequesting = false
                requestError = String(describing: error)
            }
        }
    }
}

private struct FolderStep: View {
    @Environment(AppModel.self) private var model
    @State private var isPickerPresented = false

    /// Long enough to read the saved folder name before Home appears (design §2).
    static let savedConfirmationDelay = Duration.milliseconds(1_200)

    var body: some View {
        OnboardingPage {
            SymbolImage("folder.badge.plus", size: SymbolSize.hero, color: .vcAccent)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text("Choose where files go.")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.vcPrimaryText)
            Text("Pick one folder in Files. Vital Courier creates a subfolder named Vital Courier and keeps its JSON and Markdown files there.")
                .font(.body)
                .foregroundStyle(Color.vcSecondaryText)
            Text("Edits inside that subfolder can be replaced when health data changes.")
                .font(.footnote)
                .foregroundStyle(Color.vcTertiaryText)
            switch model.folderSave {
            case .idle:
                EmptyView()
            case .saving:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Saving folder…").foregroundStyle(Color.vcSecondaryText)
                }
            case .saved(let displayPath):
                HStack(spacing: 12) {
                    SymbolImage("checkmark.circle.fill", size: SymbolSize.status, color: .vcSuccess)
                        .accessibilityHidden(true)
                    Text(FolderPathText.localized(displayPath)).font(.headline).foregroundStyle(Color.vcPrimaryText)
                }
                .accessibilityElement(children: .combine)
            case .failed(let errorText):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder couldn’t be saved")
                        .font(.headline)
                        .foregroundStyle(Color.vcPrimaryText)
                    ErrorTextView(text: errorText)
                }
            }
            Button(chooseTitle) { isPickerPresented = true }
                .buttonStyle(ProminentActionStyle())
                .disabled(isBusy)
        }
        .folderPicker(isPresented: $isPickerPresented, onPick: { model.pickFolder($0) }, onError: { model.folderSave = .failed(errorText: $0) })
        .onChange(of: model.folderSave) { _, newValue in
            guard case .saved = newValue else { return }
            Task {
                try? await Task.sleep(for: Self.savedConfirmationDelay)
                model.completeSetup()
            }
        }
    }

    private var chooseTitle: LocalizedStringKey {
        if case .failed = model.folderSave { "Choose another folder" } else { "Choose folder" }
    }

    private var isBusy: Bool {
        switch model.folderSave {
        case .saving, .saved: true
        case .idle, .failed: false
        }
    }
}
