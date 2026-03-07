import SwiftUI

private struct ProfileEditorContext: Identifiable {
  let id = UUID()
  let title: String
  let profile: SDRConnectionProfile
  let isNew: Bool
}

struct RadiosView: View {
  @EnvironmentObject private var profileStore: ProfileStore
  @State private var editorContext: ProfileEditorContext?
  @State private var isDirectoryPresented = false

  var body: some View {
    NavigationStack {
      Group {
        if profileStore.profiles.isEmpty {
          UnavailableContentView(
            title: L10n.text("No Radios Yet"),
            systemImage: "dot.radiowaves.left.and.right",
            description: L10n.text("Add a KiwiSDR, OpenWebRX or FM-DX receiver profile.")
          )
        } else {
          List {
            ForEach(profileStore.profiles) { profile in
              profileRow(for: profile)
            }
          }
          .listStyle(.insetGrouped)
        }
      }
      .navigationTitle("Radios")
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            isDirectoryPresented = true
          } label: {
            Label("Directory", systemImage: "globe")
          }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            editorContext = ProfileEditorContext(
              title: L10n.text("New Radio"),
              profile: SDRConnectionProfile.empty(),
              isNew: true
            )
          } label: {
            Label("Add radio", systemImage: "plus")
          }
        }
      }
      .sheet(isPresented: $isDirectoryPresented) {
        ReceiverDirectoryView()
      }
      .sheet(item: $editorContext) { context in
        ProfileEditorView(
          title: context.title,
          initialProfile: context.profile,
          onSave: { profile in
            profileStore.upsert(profile)
            if context.isNew {
              profileStore.updateSelection(profile.id)
            }
            editorContext = nil
          },
          onCancel: {
            editorContext = nil
          }
        )
      }
    }
  }

  @ViewBuilder
  private func profileRow(for profile: SDRConnectionProfile) -> some View {
    Button {
      profileStore.updateSelection(profile.id)
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(profile.name)
            .font(.headline)
          Text("\(profile.backend.displayName) - \(profile.endpointDescription)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        Spacer()

        if profileStore.selectedProfileID == profile.id {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button("Edit") {
        editorContext = ProfileEditorContext(
          title: L10n.text("Edit Radio"),
          profile: profile,
          isNew: false
        )
      }

      Button("Delete", role: .destructive) {
        profileStore.delete(profile)
      }
    }
    .accessibilityLabel(profile.name)
    .accessibilityHint(L10n.text("Double tap to select this receiver profile"))
    .accessibilityValue(
      profileStore.selectedProfileID == profile.id
        ? L10n.text("common.selected")
        : L10n.text("common.not_selected")
    )
  }
}
