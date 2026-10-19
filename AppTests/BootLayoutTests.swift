import CoreGraphics
import Testing

@testable import VitalCourier

@Suite struct BootLayoutTests {
  @Test func portraitRegularCentresTheSymbolAndStartsTheProgressBelowIt() {
    let layout = BootLayout(fullSize: CGSize(width: 402, height: 874), safeBottom: 34, isAccessibilitySize: false)
    #expect(layout.symbolCenter == CGPoint(x: 201, y: 437))
    #expect(layout.isCompact == false)
    #expect(layout.progressContentTop == 525)
    #expect(layout.progressContentBottom == 828)
    #expect(layout.progressTextWidth == 354)
    #expect(layout.limitsBodyToOneLine == false)
  }

  @Test func landscapeCompactStartsAtTheCanvasBottomAndLimitsTheBody() {
    let layout = BootLayout(fullSize: CGSize(width: 874, height: 402), safeBottom: 21, isAccessibilitySize: false)
    #expect(layout.isCompact == true)
    #expect(layout.progressContentTop == 261)
    #expect(layout.progressContentBottom == 369)
    #expect(layout.progressTextWidth == 420)
    #expect(layout.limitsBodyToOneLine == true)
  }

  @Test func accessibilitySizeIsCompactButKeepsTheFullBody() {
    let layout = BootLayout(fullSize: CGSize(width: 402, height: 874), safeBottom: 34, isAccessibilitySize: true)
    #expect(layout.isCompact == true)
    #expect(layout.progressContentTop == 497)
    #expect(layout.limitsBodyToOneLine == false)
  }

  @Test func compactStartsBelowFiveHundredPoints() {
    let regular = BootLayout(fullSize: CGSize(width: 400, height: 500), safeBottom: 0, isAccessibilitySize: false)
    let compact = BootLayout(fullSize: CGSize(width: 400, height: 499.5), safeBottom: 0, isAccessibilitySize: false)
    #expect(regular.isCompact == false)
    #expect(compact.isCompact == true)
  }

  @Test func portraitTextWidthIsCappedOnWideScreens() {
    let layout = BootLayout(fullSize: CGSize(width: 440, height: 956), safeBottom: 34, isAccessibilitySize: false)
    #expect(layout.progressTextWidth == 360)
  }

  @Test func aRegionSqueezedBelowZeroClampsToEmpty() {
    let layout = BootLayout(fullSize: CGSize(width: 300, height: 200), safeBottom: 60, isAccessibilitySize: false)
    #expect(layout.progressContentBottom == layout.progressContentTop)
    #expect(layout.progressRegionHeight == 0)
  }
}
