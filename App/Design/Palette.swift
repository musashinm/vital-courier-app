import SwiftUI

/// Design iOS App v2 tokens. Opaque asset colors only; never `.secondary` or `.tertiary` (they are translucent).
extension Color {
    static let vcPrimaryText = Color("VCPrimaryText")
    static let vcSecondaryText = Color("VCSecondaryText")
    static let vcTertiaryText = Color("VCTertiaryText")
    static let vcAccent = Color("VCAccent")
    static let vcSuccess = Color("VCSuccess")
    static let vcWarning = Color("VCWarning")
    static let vcError = Color("VCError")
    static let vcAppBackground = Color(uiColor: .systemGroupedBackground)
}

/// SF Symbol sizes at the Large text size (design, Spacing): scaled with Dynamic Type by `SymbolImage`.
enum SymbolSize {
    static let status: CGFloat = 24
    static let row: CGFloat = 22
    static let hero: CGFloat = 44
}
