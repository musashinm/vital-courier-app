import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VitalCourierCore

/// An SF Symbol at a design size, scaled with Dynamic Type.
struct SymbolImage: View {
  let name: String
  let color: Color
  @ScaledMetric private var size: CGFloat

  init(_ name: String, size: CGFloat, color: Color) {
    self.name = name
    self.color = color
    _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
  }

  var body: some View {
    // A fixed column, so text next to glyphs of different widths (bed, figure, heart) starts at the same x.
    Image(systemName: name)
      .font(.system(size: size))
      .foregroundStyle(color)
      .frame(width: size * 1.4)
  }
}

/// An exact saved error: monospaced, selectable, wrapping, never truncated.
struct ErrorTextView: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.footnote.monospaced())
      .foregroundStyle(Color.vcPrimaryText)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The one prominent action per screen: accent fill, white label in light mode and black in dark (design, Tokens).
struct ProminentActionStyle: ButtonStyle {
  @Environment(\.colorScheme) private var colorScheme

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, minHeight: 50)
      .padding(.horizontal, 16)
      .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
      .background(Color.vcAccent, in: RoundedRectangle(cornerRadius: 12))
      .opacity(configuration.isPressed ? 0.85 : 1)
  }
}

/// A label and value that stack vertically when they don't fit side by side.
struct DetailRow: View {
  let label: LocalizedStringKey
  let value: String

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline) {
        Text(label).foregroundStyle(Color.vcPrimaryText)
        Spacer(minLength: 12)
        Text(value).foregroundStyle(Color.vcSecondaryText).monospacedDigit().multilineTextAlignment(.trailing)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(label).foregroundStyle(Color.vcPrimaryText)
        Text(value).foregroundStyle(Color.vcSecondaryText).monospacedDigit()
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// The seven-day hint with underlined "Review access" and a chevron running on at the end of the same text, so the link wraps with the sentence and stays attached at Accessibility 5 (design §3, boards 19 and 25). The link opens the app's page in Settings (design open question 4). The tap target is the underlined words; the chevron is part of the same line.
struct SilentTypeHint: View {
  var body: some View {
    Text("This can be normal. If you expected data, review Apple Health access. \(Self.reviewAccessLink)")
      .font(.footnote)
      .foregroundStyle(Color.vcSecondaryText)
  }

  private static var reviewAccessLink: Text {
    Text("\(Text(ReviewAccess.label(linked: true)))\u{00A0}\(ReviewAccess.chevron)")
  }
}

/// What "Review access" shares between the inline hint and the standalone Home button: the app's page in Settings and the chevron that follows the label.
enum ReviewAccess {
  static var settingsURL: URL? { URL(string: UIApplication.openSettingsURLString) }

  /// The localized, underlined, accent-coloured "Review access" words. With `linked`, they also link to the Settings page.
  static func label(linked: Bool = false) -> AttributedString {
    var label = AttributedString(localized: "Review access")
    label.underlineStyle = .single
    label.foregroundColor = Color.vcAccent
    if linked, let settingsURL {
      label.link = settingsURL
    }
    return label
  }

  static var chevron: Text {
    Text(Image(systemName: "chevron.right"))
      .font(.footnote.weight(.semibold))
      .foregroundStyle(Color.vcAccent)
  }
}

/// "Review access" as a standalone action under a summary row. It opens the app's page in Settings and keeps the 44 pt touch target.
struct ReviewAccessButton: View {
  var body: some View {
    Button {
      if let settingsURL = ReviewAccess.settingsURL {
        UIApplication.shared.open(settingsURL)
      }
    } label: {
      Text("\(Text(ReviewAccess.label()))\u{00A0}\(ReviewAccess.chevron)")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.vcAccent)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(Text("Review access"))
  }
}

extension View {
  /// The system folder picker. Cancelling calls neither closure.
  func folderPicker(isPresented: Binding<Bool>, onPick: @escaping (URL) -> Void, onError: @escaping (String) -> Void)
    -> some View
  {
    fileImporter(isPresented: isPresented, allowedContentTypes: [.folder]) { result in
      switch result {
      case .success(let url): onPick(url)
      case .failure(let error): onError(String(describing: error))
      }
    }
  }
}

extension HealthType {
  var displayName: String {
    switch self {
    case .steps: String(localized: "Steps")
    case .exerciseMinutes: String(localized: "Exercise minutes")
    case .restingHeartRate: String(localized: "Resting heart rate")
    case .walkingHeartRateAverage: String(localized: "Walking heart rate average")
    case .heartRate: String(localized: "Heart rate")
    case .respiratoryRate: String(localized: "Respiratory rate")
    case .bloodGlucose: String(localized: "Blood glucose")
    case .bloodOxygen: String(localized: "Blood oxygen")
    case .sleep: String(localized: "Sleep")
    case .weight: String(localized: "Weight")
    case .menstrualFlow: String(localized: "Menstrual flow")
    case .spotting: String(localized: "Spotting")
    }
  }

  var symbolName: String {
    switch self {
    case .steps: "figure.walk"
    case .exerciseMinutes: "figure.run"
    case .restingHeartRate: "heart.fill"
    case .walkingHeartRateAverage: "heart.fill"
    case .heartRate: "heart.fill"
    case .respiratoryRate: "lungs.fill"
    case .bloodGlucose: "waveform.path.ecg.rectangle.fill"
    case .bloodOxygen: "lungs.fill"
    case .sleep: "bed.double.fill"
    case .weight: "scalemass.fill"
    case .menstrualFlow: "drop.fill"
    case .spotting: "drop"
    }
  }
}

extension RunRowOutcome {
  var color: Color {
    switch self {
    case .success: .vcSuccess
    case .locked, .notRequested: .vcSecondaryText
    case .attention: .vcWarning
    case .exportError: .vcError
    }
  }
}
