import SwiftUI
import VitalCourierCore

/// The types of one Apple Health category. It reads the live model, so turning a type off in Settings while this
/// screen is in Home's stack updates the rows, or shows the empty state when none are left.
struct CategoryDetailView: View {
  @Environment(AppModel.self) private var model
  let category: HealthCategory

  var body: some View {
    let formatter = StatusDateFormatter()
    let today = DayKey(date: model.now, timeZone: .current)
    let setupDay = model.environment.settings.setupCompletedAt.map { DayKey(date: $0, timeZone: .current) }
    let rows = HomeHealthItems.rows(of: category, enabledTypes: model.enabledTypes) { type in
      .resolve(type: type, snapshot: model.snapshot, setupDay: setupDay, today: today, formatter: formatter)
    }
    let sections = CategoryDetailSections(rows: rows)
    Group {
      if sections.isEmpty {
        ContentUnavailableView(
          "No types to show", systemImage: "rectangle.stack.badge.minus",
          description: Text("This category no longer has any types to show."))
      } else {
        List {
          if sections.needsAttention.isEmpty {
            Section { healthRows(sections.others) }
          } else {
            Section {
              healthRows(sections.needsAttention)
            } header: {
              Text("Needs attention").foregroundStyle(Color.vcTertiaryText)
            }
            if !sections.others.isEmpty {
              Section {
                healthRows(sections.others)
              } header: {
                Text("Other types").foregroundStyle(Color.vcTertiaryText)
              }
            }
          }
        }
        .listStyle(.insetGrouped)
      }
    }
    .navigationTitle(category.name())
    .navigationBarTitleDisplayMode(.inline)
  }

  private func healthRows(_ rows: [HealthRowPresentation]) -> some View {
    ForEach(rows, id: \.type) { HealthRow(presentation: $0) }
  }
}
