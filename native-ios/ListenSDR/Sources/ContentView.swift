import SwiftUI

struct ContentView: View {
  var body: some View {
    TabView {
      RadiosView()
        .tabItem {
          Label("Radios", systemImage: "dot.radiowaves.left.and.right")
        }

      ReceiverView()
        .tabItem {
          Label("Receiver", systemImage: "dial.high")
        }

      DiagnosticsView()
        .tabItem {
          Label("Diagnostics", systemImage: "waveform.path.ecg")
        }
    }
    .tint(AppTheme.tint)
    .toolbarBackground(.regularMaterial, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
    .appScreenBackground()
  }
}
