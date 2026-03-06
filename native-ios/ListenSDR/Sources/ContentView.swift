import SwiftUI

struct ContentView: View {
  @State private var frequency = 99.5
  @State private var gain = 4
  @State private var noiseReduction = true
  @State private var isListening = false

  private var frequencyText: String {
    String(format: "%.1f MHz", frequency)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Tuning") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Frequency")
              .font(.headline)
            Text(frequencyText)
              .font(.title3)
              .accessibilityLabel("Current frequency")
              .accessibilityValue(frequencyText)

            Slider(value: $frequency, in: 87.5...108.0, step: 0.1)
              .accessibilityLabel("FM frequency")
              .accessibilityHint("Swipe up or down to adjust by point one megahertz")
              .accessibilityValue(frequencyText)
          }
          .padding(.vertical, 4)

          Stepper("Gain \(gain)", value: $gain, in: 0...10)
            .accessibilityLabel("Receiver gain")
            .accessibilityValue("\(gain)")
            .accessibilityHint("Adjust signal gain from zero to ten")

          Toggle("Noise reduction", isOn: $noiseReduction)
            .accessibilityHint("Reduces background hiss")
        }

        Section("Control") {
          Button(isListening ? "Stop Listening" : "Start Listening") {
            isListening.toggle()
          }
          .accessibilityLabel(isListening ? "Stop listening" : "Start listening")
          .accessibilityHint("Double tap to toggle listening state")

          Text(isListening ? "Listening now" : "Stopped")
            .accessibilityLabel("Receiver status")
            .accessibilityValue(isListening ? "Listening now" : "Stopped")
        }
      }
      .navigationTitle("Listen SDR")
    }
  }
}

#Preview {
  ContentView()
}
