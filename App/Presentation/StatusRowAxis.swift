import SwiftUI

/// Whether a symbol-and-text row sits side by side or stacks the symbol above the text. At accessibility text
/// sizes the scaled symbol column leaves too little width, so the row stacks.
enum StatusRowAxis: Equatable {
  case horizontal
  case vertical

  init(dynamicTypeSize: DynamicTypeSize) {
    self = dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal
  }
}
