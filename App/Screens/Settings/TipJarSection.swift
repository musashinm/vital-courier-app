import SwiftUI
import VitalCourierCore

extension TipTier {
  /// App-owned names, so they follow the app's language rather than the App Store listing's.
  var displayName: LocalizedStringResource {
    switch self {
    case .smallThanks: "Small thanks"
    case .coffee: "Coffee"
    case .keepGoing: "Keep it going"
    }
  }
}

/// The optional tip jar at the bottom of Settings (design: Tip Jar).
struct TipJarSection: View {
  @Environment(AppModel.self) private var model

  private var tipJar: TipJarModel { model.tipJar }
  private var state: TipJarState { tipJar.state }

  var body: some View {
    Section {
      content
    } header: {
      Text("Support the project").foregroundStyle(Color.vcTertiaryText)
    } footer: {
      if showsFooter {
        Text("Optional one-time tips. No paywall and no recurring subscription.")
          .foregroundStyle(Color.vcTertiaryText)
      }
    }
  }

  private var showsFooter: Bool {
    switch state.phase {
    case .ready, .purchasing: true
    case .loading, .unavailable, .thanked: false
    }
  }

  @ViewBuilder private var content: some View {
    switch state.phase {
    case .loading:
      HStack(spacing: 8) {
        ProgressView()
        Text("Loading tips…").foregroundStyle(Color.vcSecondaryText)
      }
      .frame(minHeight: 44)
      .accessibilityElement(children: .combine)
    case .unavailable:
      Text("Tips aren’t available right now.")
        .foregroundStyle(Color.vcSecondaryText)
        .frame(minHeight: 44)
    case .ready, .purchasing:
      ForEach(TipTier.allCases, id: \.self) { tier in
        TipRow(
          tier: tier,
          price: tipJar.pricesByTier[tier, default: ""],
          availability: availability(of: tier),
          action: { Task { await tipJar.purchase(tier) } }
        )
      }
      if state.isAwaitingApproval { pendingRow }
      if state.showsFailure {
        Text("Couldn’t complete the tip. Try again.")
          .foregroundStyle(Color.vcError)
          .frame(minHeight: 44)
      }
    case .thanked:
      Text("Thank you for supporting Vital Courier.")
        .foregroundStyle(Color.vcPrimaryText)
        .frame(minHeight: 44)
    }
  }

  private var pendingRow: some View {
    HStack(spacing: 8) {
      Text("Waiting for approval.").foregroundStyle(Color.vcSecondaryText)
      Spacer(minLength: 8)
      SymbolImage("clock", size: SymbolSize.row, color: .vcSecondaryText)
        .accessibilityHidden(true)
    }
    .frame(minHeight: 44)
    .accessibilityElement(children: .combine)
  }

  private func availability(of tier: TipTier) -> TipRow.Availability {
    guard case .purchasing(let purchasingTier) = state.phase else { return .ready }
    return purchasingTier == tier ? .purchasing : .blockedByOtherPurchase
  }
}

/// Runs the tip jar's lifecycle once per visit to Settings. It sits on the screen's `List`, not on the section: a `List` header or row is recycled while scrolling, which would cancel the load and clear Failed on every scroll.
private struct TipJarLifecycle: ViewModifier {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @State private var hasAnnouncedPurchasing = false

  private var tipJar: TipJarModel { model.tipJar }

  func body(content: Content) -> some View {
    content
      .task { await tipJar.loadIfNeeded() }
      .onAppear { tipJar.sectionAppeared() }
      .onChange(of: tipJar.state) { oldState, newState in announceChange(from: oldState, to: newState) }
      // StoreKit has no public "sheet dismissed" callback; the scene returning to active is the closest signal.
      .onChange(of: scenePhase) { oldPhase, newPhase in announcePurchasingAfterSheet(from: oldPhase, to: newPhase) }
  }

  /// Failed, Pending and Thanked are each announced once, when they replace Purchasing.
  private func announceChange(from oldState: TipJarState, to newState: TipJarState) {
    if case .purchasing = newState.phase, oldState.phase != newState.phase {
      hasAnnouncedPurchasing = false
    }
    if newState.phase == .thanked, oldState.phase != .thanked {
      announce(String(localized: "Thank you for supporting Vital Courier."))
    } else if newState.isAwaitingApproval, !oldState.isAwaitingApproval {
      announce(String(localized: "Waiting for approval."))
    } else if newState.showsFailure, !oldState.showsFailure {
      announce(String(localized: "Couldn’t complete the tip. Try again."))
    }
  }

  /// "Purchasing" is announced at most once per purchase, when the app returns from Apple's sheet and the purchase is still running.
  private func announcePurchasingAfterSheet(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
    guard case .purchasing = tipJar.state.phase, newPhase == .active, oldPhase != .active, !hasAnnouncedPurchasing
    else { return }
    hasAnnouncedPurchasing = true
    announce(String(localized: "Purchasing…"))
  }

  private func announce(_ message: String) {
    AccessibilityNotification.Announcement(message).post()
  }
}

extension View {
  /// Loads the tip jar's products, resets its transient failure and announces its state changes, once per visit to the screen holding the section.
  func tipJarLifecycle() -> some View {
    modifier(TipJarLifecycle())
  }
}

/// One tip tier as a button: name leading, price trailing, stacked when they don't fit side by side.
struct TipRow: View {
  enum Availability {
    case ready, purchasing, blockedByOtherPurchase
  }

  let tier: TipTier
  let price: String
  let availability: Availability
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ViewThatFits(in: .horizontal) {
        // A ProgressView has no text baseline, so a purchasing row centres its name on the spinner and text instead.
        HStack(alignment: availability == .purchasing ? .center : .firstTextBaseline) {
          tierName
          Spacer(minLength: 12)
          trailing
        }
        VStack(alignment: .leading, spacing: 4) {
          tierName
          trailing
        }
      }
      .frame(minHeight: 44)
      .accessibilityElement(children: .combine)
      // The explicit row colours hide the native disabled look, so the blocked rows dim to the mockup's opacity.
      .opacity(availability == .blockedByOtherPurchase ? 0.42 : 1)
    }
    .disabled(availability == .blockedByOtherPurchase)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(availability == .ready ? Text("Optional one-time tip.") : Text(verbatim: ""))
    .accessibilityValue(accessibilityValue)
  }

  private var tierName: some View {
    Text(tier.displayName).foregroundStyle(Color.vcPrimaryText)
  }

  @ViewBuilder private var trailing: some View {
    if availability == .purchasing {
      HStack(spacing: 8) {
        ProgressView()
        Text("Purchasing…").foregroundStyle(Color.vcSecondaryText)
      }
    } else {
      Text(price).foregroundStyle(Color.vcAccent).multilineTextAlignment(.trailing)
    }
  }

  private var accessibilityLabel: Text {
    let tierName = String(localized: tier.displayName)
    switch availability {
    case .purchasing: return Text(String(localized: "\(tierName), purchase in progress"))
    case .ready, .blockedByOtherPurchase: return Text(verbatim: "\(tierName), \(price)")
    }
  }

  private var accessibilityValue: Text {
    switch availability {
    case .blockedByOtherPurchase: Text("Unavailable while another purchase is in progress.")
    case .ready, .purchasing: Text(verbatim: "")
    }
  }
}
