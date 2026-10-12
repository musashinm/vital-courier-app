import SwiftUI

struct BootView: View {
    let showsProgress: Bool
    let safeBottom: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { screenProxy in
            let layout = BootLayout(fullSize: screenProxy.size, safeBottom: safeBottom, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
            ZStack {
                Color.vcLaunchBackground
                Image("LaunchCircuit")
                    .interpolation(.high)
                    .accessibilityHidden(true)
                    .position(layout.symbolCenter)
                progress(in: layout)
                    .opacity(showsProgress ? 1 : 0)
                    .accessibilityHidden(!showsProgress)
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showsProgress)
    }

    /// Scrolls only when the stack doesn't fit its region, in every layout branch.
    private func progress(in layout: BootLayout) -> some View {
        ViewThatFits(in: .vertical) {
            progressStack(in: layout)
            ScrollView { progressStack(in: layout) }
        }
        .frame(width: layout.progressTextWidth, height: layout.progressRegionHeight, alignment: .top)
        .padding(.vertical, BootLayout.progressWrapperInset)
        .position(x: layout.symbolCenter.x, y: layout.progressContentTop + layout.progressRegionHeight / 2)
    }

    private func progressStack(in layout: BootLayout) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing Vital Courier…")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.vcPrimaryText)
            Text("Checking the local copy and export folder.")
                .font(.body)
                .foregroundStyle(Color.vcSecondaryText)
                .lineLimit(layout.limitsBodyToOneLine ? 1 : nil)
                .truncationMode(.tail)
                .accessibilityLabel(Text("Checking the local copy and export folder."))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}
