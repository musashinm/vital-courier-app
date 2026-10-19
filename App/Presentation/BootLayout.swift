import CoreGraphics

/// BootView geometry (design App Icon v2, Layout). The launch symbol sits at the full-screen centre so it lines up
/// with the static launch screen (`UIImageRespectsSafeAreaInsets` is false); the delayed progress copy fills the space below it.
struct BootLayout: Equatable {
  static let launchImageSide: CGFloat = 120
  static let compactHeightLimit: CGFloat = 500
  static let regularProgressGap: CGFloat = 28
  static let progressWrapperInset: CGFloat = 8
  static let progressBottomInset: CGFloat = 12
  static let contentSideInset: CGFloat = 24
  static let portraitTextWidthCap: CGFloat = 360
  static let landscapeTextWidthCap: CGFloat = 420

  let symbolCenter: CGPoint
  let isCompact: Bool
  let progressContentTop: CGFloat
  let progressContentBottom: CGFloat
  let progressTextWidth: CGFloat
  let limitsBodyToOneLine: Bool

  /// - Parameters:
  ///   - fullSize: the whole screen, measured with safe areas ignored.
  ///   - safeBottom: the real bottom safe-area inset, read outside the ignored-safe-area geometry.
  init(fullSize: CGSize, safeBottom: CGFloat, isAccessibilitySize: Bool) {
    symbolCenter = CGPoint(x: fullSize.width / 2, y: fullSize.height / 2)
    isCompact = fullSize.height < Self.compactHeightLimit || isAccessibilitySize
    let canvasBottom = fullSize.height / 2 + Self.launchImageSide / 2
    progressContentTop = canvasBottom + (isCompact ? 0 : Self.regularProgressGap)
    progressContentBottom = max(progressContentTop, fullSize.height - safeBottom - Self.progressBottomInset)
    let widthCap = fullSize.width > fullSize.height ? Self.landscapeTextWidthCap : Self.portraitTextWidthCap
    progressTextWidth = max(0, min(fullSize.width - 2 * Self.contentSideInset, widthCap))
    limitsBodyToOneLine = isCompact && !isAccessibilitySize
  }

  var progressRegionHeight: CGFloat { progressContentBottom - progressContentTop }
}
