import SwiftUI
import Testing

@testable import VitalCourier

@Suite struct StatusRowAxisTests {
  @Test func largeTextSizeKeepsTheRowHorizontal() {
    #expect(StatusRowAxis(dynamicTypeSize: .large) == .horizontal)
  }

  @Test func largestNonAccessibilityTextSizeKeepsTheRowHorizontal() {
    #expect(StatusRowAxis(dynamicTypeSize: .xxxLarge) == .horizontal)
  }

  @Test func firstAccessibilityTextSizeStacksTheRow() {
    #expect(StatusRowAxis(dynamicTypeSize: .accessibility1) == .vertical)
  }

  @Test func largestAccessibilityTextSizeStacksTheRow() {
    #expect(StatusRowAxis(dynamicTypeSize: .accessibility5) == .vertical)
  }
}
