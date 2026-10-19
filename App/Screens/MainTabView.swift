import SwiftUI

struct MainTabView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    TabView(selection: $model.selectedTab) {
      Tab("Home", systemImage: "house", value: AppTab.home) {
        NavigationStack { HomeView() }
      }
      Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
        NavigationStack { HistoryView() }
      }
      Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
        NavigationStack { SettingsView() }
      }
    }
  }
}
