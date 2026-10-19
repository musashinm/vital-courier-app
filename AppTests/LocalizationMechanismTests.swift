import Foundation
import Testing

@testable import VitalCourier

@Suite struct LocalizationMechanismTests {
  @Test func eachLanguageBundleResolvesAPlainEntry() {
    #expect(AppLocalization.english.string("today") == "today")
    #expect(AppLocalization.portuguese.string("today") == "hoje")
  }

  @Test func eachLanguageBundleResolvesPlurals() {
    #expect(AppLocalization.english.string("\(1) days updated") == "1 day updated")
    #expect(AppLocalization.english.string("\(2) days updated") == "2 days updated")
    #expect(AppLocalization.portuguese.string("\(1) days updated") == "1 dia atualizado")
    #expect(AppLocalization.portuguese.string("\(2) days updated") == "2 dias atualizados")
    // CLDR Portuguese puts 0 in `one`. This is why counts of 0 get their own key (spec Decision 7).
    #expect(AppLocalization.portuguese.string("\(0) days updated") == "0 dia atualizado")
  }
}
