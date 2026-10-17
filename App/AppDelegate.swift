import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Here, not in a view: HealthKit and BGAppRefreshTask background launches never build a scene.
        let environment = AppEnvironment.shared
        BackgroundRefresh.register(environment: environment)
        if environment.settings.setupCompletedAt != nil {
            ObserverRegistration.start(environment: environment)
        }
        // Every launch, set up or not: an interrupted or Ask to Buy tip arrives here, not through a view.
        TipTransactionListener.start(settings: environment.settings)
        return true
    }
}
