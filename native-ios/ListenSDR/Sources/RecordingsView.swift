import ListenSDRCore
import SwiftUI

struct RecordingsView: View {
  @EnvironmentObject private var recordingStore: RecordingStore
  @State private var sharedRecordingURL: URL?

  var body: some View {
    List {
      Section {
        if recordingStore.recordings.isEmpty {
          Text(L10n.text("recordings.empty"))
            .foregroundStyle(.secondary)
        } else {
          ForEach(recordingStore.recordings) { recording in
            Button {
              sharedRecordingURL = recordingStore.shareURL(for: recording)
            } label: {
              let createdAtText = recording.createdAt.formatted(date: .abbreviated, time: .shortened)

              VStack(alignment: .leading, spacing: 6) {
                Text(recording.displayFileName)
                  .font(.headline)

                Text(recording.receiverName)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)

                Text(
                  L10n.text(
                    "recordings.entry.detail",
                    FrequencyFormatter.mhzText(fromHz: recording.frequencyHz),
                    recording.backend.displayName,
                    recording.format.localizedTitle
                  )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text(
                  [
                    L10n.text("recordings.entry.created", createdAtText),
                    L10n.text("recordings.entry.duration", recording.durationText)
                  ].joined(separator: " | ")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button {
                sharedRecordingURL = recordingStore.shareURL(for: recording)
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
    }
    .voiceOverStable()
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
