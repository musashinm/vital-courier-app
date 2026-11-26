import Foundation
import Testing
import VitalCourierCore

@testable import VitalCourier

@Suite struct CategoryPresentationTests {
  let today = day("2026-11-16")
  let english = StatusDateFormatter(localization: .english, timeZone: saoPaulo)
  let portuguese = StatusDateFormatter(localization: .portuguese, timeZone: saoPaulo)

  func row(_ type: HealthType, day dayText: String?, silent: Bool = false) -> HealthRowPresentation {
    HealthRowPresentation(type: type, valueText: "", isSilent: silent, latestDay: dayText.map(day))
  }

  func category(_ category: HealthCategory, _ rows: [HealthRowPresentation]) -> CategoryPresentation {
    CategoryPresentation(category: category, rows: rows)
  }

  /// A category with `count` rows, the first `silent` of them silent, for the label counts.
  func filler(_ count: Int, silent: Int = 0, day dayText: String? = nil) -> [HealthRowPresentation] {
    (0..<count).map { row(.steps, day: dayText, silent: $0 < silent) }
  }

  func resolveWithoutData(_ type: HealthType) -> HealthRowPresentation { row(type, day: nil) }

  @Test func todaysTypesGroupAsTheSpecSays() {
    let withoutCycle = HomeHealthItems.items(
      enabledTypes: HealthType.enabledTypes(cycleTrackingEnabled: false), resolve: resolveWithoutData)
    #expect(
      withoutCycle.map(\.summary) == [
        "activity 7", "bodyMeasurements 2", "heart 5", "walkingSpeed", "respiratory 2", "sleep", "bloodGlucose",
      ])
    let withCycle = HomeHealthItems.items(
      enabledTypes: HealthType.enabledTypes(cycleTrackingEnabled: true), resolve: resolveWithoutData)
    #expect(
      withCycle.map(\.summary)
        == [
          "activity 7", "bodyMeasurements 2", "cycleTracking 2", "heart 5", "walkingSpeed", "respiratory 2", "sleep",
          "bloodGlucose",
        ])
  }

  @Test func aCategoryWithNoEnabledTypeIsOmitted() {
    let items = HomeHealthItems.items(enabledTypes: [.steps], resolve: resolveWithoutData)
    #expect(items == [.type(row(.steps, day: nil))])
  }

  @Test func warningOutranksLatest() {
    let heart = category(
      .heart, [row(.heartRate, day: "2026-11-16"), row(.restingHeartRate, day: "2026-11-01", silent: true)])
    #expect(heart.summaryText(formatter: english, today: today) == "2 types · 1 silent for a week")
    #expect(heart.summaryText(formatter: portuguese, today: today) == "2 tipos · 1 sem dados há uma semana")
  }

  @Test func latestSummaryUsesTheNewestDay() {
    let activity = category(.activity, [row(.steps, day: "2026-11-14"), row(.exerciseMinutes, day: "2026-11-16")])
    #expect(activity.summaryText(formatter: english, today: today) == "2 types · Latest today")
    #expect(activity.summaryText(formatter: portuguese, today: today) == "2 tipos · Mais recente: hoje")
    let older = category(.activity, [row(.steps, day: "2026-09-20"), row(.exerciseMinutes, day: "2026-09-24")])
    #expect(older.summaryText(formatter: english, today: today) == "2 types · Latest Sep 24")
  }

  @Test func noDataSummary() {
    let activity = category(.activity, [row(.steps, day: nil), row(.exerciseMinutes, day: nil)])
    #expect(activity.summaryText(formatter: english, today: today) == "2 types · No data yet")
    #expect(activity.summaryText(formatter: portuguese, today: today) == "2 tipos · Nenhum dado ainda")
  }

  @Test func cycleCategoryTalksAboutEntries() {
    let logged = category(.cycleTracking, [row(.menstrualFlow, day: "2026-09-24"), row(.spotting, day: nil)])
    #expect(logged.summaryText(formatter: english, today: today) == "2 types · Latest entry Sep 24")
    #expect(logged.summaryText(formatter: portuguese, today: today) == "2 tipos · Último registro: 24 de set.")
    let empty = category(.cycleTracking, [row(.menstrualFlow, day: nil), row(.spotting, day: nil)])
    #expect(empty.summaryText(formatter: english, today: today) == "2 types · No entries yet")
    #expect(empty.summaryText(formatter: portuguese, today: today) == "2 tipos · Nenhum registro ainda")
  }

  @Test func latestDayComesFromEveryStoragePath() {
    let daily = category(.cycleTracking, [row(.steps, day: "2026-11-10"), row(.menstrualFlow, day: nil)])
    #expect(daily.latestDay == day("2026-11-10"))
    let flow = category(.cycleTracking, [row(.menstrualFlow, day: "2026-11-12"), row(.spotting, day: "2026-11-03")])
    #expect(flow.latestDay == day("2026-11-12"))
    let spotting = category(
      .cycleTracking, [row(.menstrualFlow, day: "2026-11-03"), row(.spotting, day: "2026-11-12")])
    #expect(spotting.latestDay == day("2026-11-12"))
  }

  @Test func accessibilityLabels() {
    let silentHeart = category(.heart, filler(6, silent: 2, day: "2026-11-16"))
    #expect(
      silentHeart.accessibilityLabel(formatter: english, today: today)
        == "Heart. 6 types. 2 types have been silent for a week.")
    #expect(
      silentHeart.accessibilityLabel(formatter: portuguese, today: today)
        == "Coração. 6 tipos. 2 tipos estão sem dados há uma semana.")

    let activity = category(.activity, filler(12, day: "2026-11-16"))
    #expect(activity.accessibilityLabel(formatter: english, today: today) == "Activity. 12 types. Latest today.")
    #expect(
      activity.accessibilityLabel(formatter: portuguese, today: today) == "Atividade. 12 tipos. Mais recente: hoje")

    let olderActivity = category(.activity, filler(12, day: "2026-09-24"))
    #expect(
      olderActivity.accessibilityLabel(formatter: portuguese, today: today)
        == "Atividade. 12 tipos. Mais recente: 24 de set.")

    let nutrition = category(.nutrition, filler(39))
    #expect(nutrition.accessibilityLabel(formatter: english, today: today) == "Nutrition. 39 types. No data yet.")
    #expect(
      nutrition.accessibilityLabel(formatter: portuguese, today: today) == "Nutrição. 39 tipos. Nenhum dado ainda.")

    let cycle = category(.cycleTracking, [row(.menstrualFlow, day: "2026-09-24"), row(.spotting, day: nil)])
    #expect(
      cycle.accessibilityLabel(formatter: english, today: today) == "Cycle Tracking. 2 types. Latest entry Sep 24.")
    #expect(
      cycle.accessibilityLabel(formatter: portuguese, today: today)
        == "Acompanhamento do ciclo. 2 tipos. Último registro: 24 de set.")

    let noEntries = category(.cycleTracking, [row(.menstrualFlow, day: nil), row(.spotting, day: nil)])
    #expect(
      noEntries.accessibilityLabel(formatter: english, today: today) == "Cycle Tracking. 2 types. No entries yet.")
    #expect(
      noEntries.accessibilityLabel(formatter: portuguese, today: today)
        == "Acompanhamento do ciclo. 2 tipos. Nenhum registro ainda.")
  }

  @Test func singularFormsResolve() {
    let heart = category(.heart, [row(.heartRate, day: "2026-11-16", silent: true)])
    #expect(
      heart.accessibilityLabel(formatter: english, today: today)
        == "Heart. 1 type. 1 type has been silent for a week.")
    #expect(
      heart.accessibilityLabel(formatter: portuguese, today: today)
        == "Coração. 1 tipo. 1 tipo está sem dados há uma semana.")
    #expect(heart.summaryText(formatter: english, today: today) == "1 type · 1 silent for a week")
  }

  @Test func detailPutsSilentTypesFirstAlphabetically() {
    let rows = [
      row(.heartRate, day: "2026-11-16"),
      row(.walkingHeartRateAverage, day: nil, silent: true),
      row(.restingHeartRate, day: nil, silent: true),
    ]
    let sections = CategoryDetailSections(rows: rows)
    #expect(sections.needsAttention.map(\.type) == [.restingHeartRate, .walkingHeartRateAverage])
    #expect(sections.others.map(\.type) == [.heartRate])

    let quiet = CategoryDetailSections(rows: [
      row(.walkingHeartRateAverage, day: nil), row(.restingHeartRate, day: nil), row(.heartRate, day: nil),
    ])
    #expect(quiet.needsAttention.isEmpty)
    #expect(quiet.others.map(\.type) == [.heartRate, .restingHeartRate, .walkingHeartRateAverage])

    let reversed = CategoryDetailSections(rows: rows) { type in
      String(type.displayName.reversed())
    }
    let expected = rows.filter(\.isSilent).sorted {
      String($0.type.displayName.reversed()).localizedStandardCompare(String($1.type.displayName.reversed()))
        == .orderedAscending
    }
    #expect(reversed.needsAttention.map(\.type) == expected.map(\.type))
  }

  @Test func detailForACategoryWithNoEnabledTypesIsEmpty() {
    let off = HomeHealthItems.rows(
      of: .cycleTracking, enabledTypes: HealthType.enabledTypes(cycleTrackingEnabled: false),
      resolve: resolveWithoutData)
    #expect(off.isEmpty)
    #expect(CategoryDetailSections(rows: []).isEmpty)
    let on = HomeHealthItems.rows(
      of: .cycleTracking, enabledTypes: HealthType.enabledTypes(cycleTrackingEnabled: true),
      resolve: resolveWithoutData)
    #expect(on.count == 2)
  }
}

extension HomeHealthItem {
  /// A short label for ordering assertions: a type's name, or a category's name and row count.
  fileprivate var summary: String {
    switch self {
    case .type(let row): "\(row.type)"
    case .category(let presentation): "\(presentation.category) \(presentation.typeCount)"
    }
  }
}
