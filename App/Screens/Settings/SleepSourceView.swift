import SwiftUI

struct SleepSourceView: View {
    @Environment(AppModel.self) private var model

    static let footer = "Automatic uses Apple Watch when it has data, then the source with the most asleep time. If you choose a source, Vital Courier uses it when available, then the same fallback. Changing this rebuilds affected daily notes."

    var body: some View {
        let sources = model.sleepSources
        List {
            Section {
                ChoiceRow(title: "Automatic", isSelected: sources.selected == nil, isSaving: sources.isSaving) {
                    sources.choose(nil)
                }
                ForEach(sources.names, id: \.self) { name in
                    ChoiceRow(title: name, isSelected: sources.selected == name, isSaving: sources.isSaving) {
                        sources.choose(name)
                    }
                }
            } footer: {
                Text(Self.footer).foregroundStyle(Color.vcTertiaryText)
            }
            if let saveError = sources.saveError {
                Section {
                    HStack(spacing: 12) {
                        SymbolImage("exclamationmark.circle.fill", size: SymbolSize.status, color: .vcError)
                            .accessibilityHidden(true)
                        Text("Sleep source couldn’t be saved").font(.headline).foregroundStyle(Color.vcPrimaryText)
                    }
                    .accessibilityElement(children: .combine)
                    ErrorTextView(text: saveError)
                }
            }
            if let loadError = sources.loadError {
                Section { ErrorTextView(text: loadError) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sleep source")
        .navigationBarTitleDisplayMode(.inline)
        .task { await sources.load() }
    }
}

private struct ChoiceRow: View {
    let title: String
    let isSelected: Bool
    let isSaving: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Color.vcPrimaryText)
                Spacer()
                if isSelected && isSaving {
                    ProgressView()
                }
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.vcAccent)
                }
            }
            .frame(minHeight: 44)
        }
        .disabled(isSaving)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
