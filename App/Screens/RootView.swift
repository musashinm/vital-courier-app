import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bootPresentation = BootPresentation()
    @State private var overlayRemovalTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if model.phase != .booting {
                destination
                    .opacity(bootPresentation.rootOpacity)
                    .allowsHitTesting(bootPresentation.rootIsInteractive)
                    .accessibilityHidden(!bootPresentation.rootIsInteractive)
            }
            if bootPresentation.overlayVisible {
                // Respects the safe area so the real bottom inset is readable; BootView itself ignores it.
                GeometryReader { safeAreaProxy in
                    BootView(showsProgress: model.showsBootProgress, safeBottom: safeAreaProxy.safeAreaInsets.bottom)
                }
                .opacity(bootPresentation.bootOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(model.phase != .booting)
            }
        }
        .onChange(of: model.phase, initial: true) { oldPhase, newPhase in
            syncBootPresentation(newPhase: newPhase, isInitial: oldPhase == newPhase)
        }
        .task { await model.boot() }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && oldPhase != .active { model.sceneBecameActive() }
            if newPhase == .background { model.sceneEnteredBackground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalCourierRunFinished).receive(on: DispatchQueue.main)) { _ in
            Task { @MainActor in await model.refreshStatus() }
        }
        .onAppear { bootPresentation.completeInterruptedFade(phaseIsBooting: model.phase == .booting) }
        .onDisappear {
            overlayRemovalTask?.cancel()
            bootPresentation.completeInterruptedFade(phaseIsBooting: model.phase == .booting)
        }
    }

    @ViewBuilder private var destination: some View {
        switch model.phase {
        case .booting: EmptyView()
        case .blocked(let errorText): BlockerView(errorText: errorText)
        case .onboarding: OnboardingView()
        case .ready: MainTabView()
        }
    }

    /// `isInitial` is true only for `onChange(initial:)`'s first call, the one time old and new phase are equal.
    private func syncBootPresentation(newPhase: AppModel.Phase, isInitial: Bool) {
        switch bootPresentation.step(phaseIsBooting: newPhase == .booting, isInitial: isInitial, reduceMotion: reduceMotion) {
        case .none:
            return
        case .cut:
            overlayRemovalTask?.cancel()
            bootPresentation.showRootImmediately()
        case .fade:
            withAnimation(.easeOut(duration: 0.18)) { bootPresentation.beginFade() }
            overlayRemovalTask?.cancel()
            overlayRemovalTask = Task { @MainActor in
                try? await Task.sleep(for: BootPresentation.fadeDuration)
                guard !Task.isCancelled, model.phase != .booting else { return }
                bootPresentation.finishFade()
            }
        }
    }
}
