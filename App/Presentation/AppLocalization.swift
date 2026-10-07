import Foundation

/// Where user-facing words come from: the bundle holding the catalog's strings, and the locale for numbers and dates. Production uses `.system`; tests pass one language's `.lproj` bundle, since `String(localized:locale:)` takes its locale for formatting, not for choosing the translation (spec Decision 8).
struct AppLocalization {
    let bundle: Bundle
    let locale: Locale

    static var system: AppLocalization {
        AppLocalization(bundle: .main, locale: .current)
    }

    func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: bundle, locale: locale)
    }

    /// For an English text that needs two translations, keyed apart by `key`.
    func string(_ key: StaticString, defaultValue: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: defaultValue, bundle: bundle, locale: locale)
    }
}
