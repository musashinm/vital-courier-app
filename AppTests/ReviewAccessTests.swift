import Foundation
import Testing

@testable import VitalCourier

@Suite struct ReviewAccessTests {
  @Test func labelIsTheLocalizedWordsOnlyAndUnderlined() {
    let label = ReviewAccess.label()

    #expect(String(label.characters) == String(localized: "Review access"))
    #expect(label.underlineStyle == .single)
    #expect(label.link == nil)
  }

  @Test func linkedLabelPointsAtSettings() {
    #expect(ReviewAccess.label(linked: true).link == ReviewAccess.settingsURL)
  }
}
