import SwiftUI

@main
struct VitalCourierApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            Text("Vital Courier")
                .foregroundStyle(Color.vcPrimaryText)
                .tint(Color.vcAccent)
        }
    }
}
