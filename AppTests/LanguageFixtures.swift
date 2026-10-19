import Foundation
import VitalCourierCore

@testable import VitalCourier

let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!

func date(_ iso: String) -> Date {
  try! Date(iso, strategy: .iso8601)
}

func day(_ text: String) -> DayKey {
  DayKey(text)!
}

extension AppLocalization {
  static var english: AppLocalization { AppLocalization(language: "en", locale: Locale(identifier: "en_US")) }
  static var portuguese: AppLocalization { AppLocalization(language: "pt-BR", locale: Locale(identifier: "pt_BR")) }

  /// One language's strings from the app bundle, so a test renders that language on any simulator.
  init(language: String, locale: Locale) {
    // Found through an app class, so it is the app's bundle whatever the test host's main bundle is.
    let appBundle = Bundle(for: AppEnvironment.self)
    let languagePath = appBundle.path(forResource: language, ofType: "lproj")!
    self.init(bundle: Bundle(path: languagePath)!, locale: locale)
  }
}
