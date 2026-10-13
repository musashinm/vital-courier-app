import Foundation
import Testing
@testable import VitalCourier

@Suite struct AppLinksTests {
    @Test func privacyPolicyOpensThePageInTheAppLanguage() {
        #expect(AppLinks.privacyPolicy(in: .english)?.absoluteString == "https://vitalcourier.app/privacy")
        #expect(AppLinks.privacyPolicy(in: .portuguese)?.absoluteString == "https://vitalcourier.app/pt-br/privacy")
    }
}
