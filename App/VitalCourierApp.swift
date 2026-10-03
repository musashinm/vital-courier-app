import SwiftUI

@main
struct VitalCourierApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel(environment: .shared)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Color.vcAccent)
        }
    }
}
