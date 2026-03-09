import SwiftUI

struct ContentView: View {
  var body: some View {
    TabView {
      ReceiverView()
        .tabItem {
          Label("Receiver", systemImage: "dial.high")
        }

      RadiosView()
        .tabItem {
          Label("Radios", systemImage: "dot.radiowaves.left.and.right")
        }

      SettingsView()
        .tabItem {
          Label("Settings", systemImage: "gearshape")
        }
    }
    .tint(AppTheme.tint)
    .toolbarBackground(.regularMaterial, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
    .appScreenBackground()
  }
}
