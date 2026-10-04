import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .booting: BootView(showsProgress: model.showsBootProgress)
            case .blocked(let errorText): BlockerView(errorText: errorText)
            case .onboarding: OnboardingView()
            case .ready: MainTabView()
            }
        }
        .task { await model.boot() }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && oldPhase != .active { model.sceneBecameActive() }
            if newPhase == .background { model.sceneEnteredBackground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vitalCourierRunFinished).receive(on: DispatchQueue.main)) { _ in
            Task { @MainActor in await model.refreshStatus() }
        }
    }
}
