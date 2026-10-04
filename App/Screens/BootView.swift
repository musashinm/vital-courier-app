import SwiftUI

struct BootView: View {
    let showsProgress: Bool

    var body: some View {
        ZStack {
            Color.vcAppBackground.ignoresSafeArea()
            if showsProgress {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing Vital Courier…")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.vcPrimaryText)
                    Text("Checking the local copy and export folder.")
                        .font(.body)
                        .foregroundStyle(Color.vcSecondaryText)
                }
                .multilineTextAlignment(.center)
                .padding(24)
            }
        }
    }
}
