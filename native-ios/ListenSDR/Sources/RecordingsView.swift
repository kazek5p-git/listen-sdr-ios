import SwiftUI
import UIKit

struct RecordingsView: View {
  @EnvironmentObject private var recordingStore: RecordingStore
  @State private var sharedRecordingURL: URL?

  var body: some View {
    List {
      if recordingStore.recordings.isEmpty {
        Text(L10n.text("recordings.empty"))
          .foregroundStyle(.secondary)
      } else {
        ForEach(recordingStore.recordings) { recording in
          Button {
            sharedRecordingURL = recording.fileURL
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(recording.title)
                .font(.headline)

              Text(FrequencyFormatter.mhzText(fromHz: recording.frequencyHz))
                .font(.subheadline)
                .foregroundStyle(.secondary)

              Text(
                L10n.text(
                  "recordings.entry.detail",
                  recording.backend.displayName,
                  recording.format.localizedTitle,
                  recording.finishedAt.formatted(date: .abbreviated, time: .shortened)
                )
              )
              .font(.footnote)
              .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
              sharedRecordingURL = recording.fileURL
            } label: {
              Label(L10n.text("recordings.share"), systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
              recordingStore.delete(recording)
            } label: {
              Label(L10n.text("Delete"), systemImage: "trash")
            }
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
    .navigationTitle(L10n.text("recordings.section"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      recordingStore.refresh()
    }
    .sheet(
      isPresented: Binding(
        get: { sharedRecordingURL != nil },
        set: { isPresented in
          if !isPresented {
            sharedRecordingURL = nil
          }
        }
      )
    ) {
      if let url = sharedRecordingURL {
        ShareSheet(items: [url])
      }
    }
  }
}

private struct ShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
