import SwiftUI

/// A Home row for an Apple Health category with two or more enabled types: name, then a count and latest day.
struct CategoryRow: View {
  let presentation: CategoryPresentation
  let summary: String
  let accessibilityLabel: String

  private var showsWarning: Bool { presentation.silentCount > 0 }

  var body: some View {
    NavigationLink(value: presentation.category) {
      SymbolTextRow {
        SymbolImage(presentation.category.symbolName, size: SymbolSize.row, color: .vcSecondaryText)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(presentation.category.name())
            .font(.body)
            .foregroundStyle(Color.vcPrimaryText)
          summaryLine
        }
      }
      .frame(minHeight: 56, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint(Text("Shows the health data types in this category."))
    }
  }

  @ViewBuilder private var summaryLine: some View {
    if showsWarning {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "exclamationmark.circle")
          .font(.subheadline)
          .foregroundStyle(Color.vcWarning)
          .accessibilityHidden(true)
        summaryText
      }
    } else {
      summaryText
    }
  }

  private var summaryText: some View {
    Text(summary)
      .font(.subheadline)
      .foregroundStyle(Color.vcSecondaryText)
  }
}
