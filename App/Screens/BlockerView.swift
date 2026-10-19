import SwiftUI
import UIKit

/// Design §7: replaces the whole root; never offers to delete or reset.
struct BlockerView: View {
  @Environment(AppModel.self) private var model
  let errorText: String

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SymbolImage("externaldrive.badge.exclamationmark", size: SymbolSize.hero, color: .vcError)
          .frame(maxWidth: .infinity)
          .accessibilityHidden(true)
        Text("Vital Courier couldn’t open its local data.")
          .font(.title2.weight(.bold))
          .foregroundStyle(Color.vcPrimaryText)
        Text("Your local copy was not deleted. Vital Courier won’t read or write health data until this is fixed.")
          .font(.body)
          .foregroundStyle(Color.vcSecondaryText)
        ErrorTextView(text: errorText)
          .padding(12)
          .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        if model.isRetryingStore {
          ProgressView()
            .frame(maxWidth: .infinity)
        }
        Button("Try again") {
          Task { await model.retryStore() }
        }
        .buttonStyle(ProminentActionStyle())
        .disabled(model.isRetryingStore)
        Button("Copy error") {
          UIPasteboard.general.string = errorText
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(model.isRetryingStore)
      }
      .padding(.horizontal, 24)
      .padding(.top, 32)
      .padding(.bottom, 24)
    }
    .background(Color.vcAppBackground)
  }
}
