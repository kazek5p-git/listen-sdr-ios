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
          .scrollContentBackground(.hidden)
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
      .appScreenBackground()
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
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: backendIconName(for: profile.backend))
          .font(.headline)
          .foregroundStyle(backendAccent(for: profile.backend))
          .frame(width: 34, height: 34)
          .background(
            backendAccent(for: profile.backend).opacity(0.16),
            in: Circle()
          )
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 6) {
          Text(profile.name)
            .font(.headline)

          Text(profile.backend.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.chipFill, in: Capsule())

          Text(profile.endpointDescription)
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
      .appCardContainer()
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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

  private func backendIconName(for backend: SDRBackend) -> String {
    switch backend {
    case .kiwiSDR:
      return "dot.radiowaves.left.and.right"
    case .openWebRX:
      return "antenna.radiowaves.left.and.right"
    case .fmDxWebserver:
      return "dot.scope"
    }
  }

  private func backendAccent(for backend: SDRBackend) -> Color {
    switch backend {
    case .kiwiSDR:
      return AppTheme.tint
    case .openWebRX:
      return AppTheme.accent
    case .fmDxWebserver:
      return .orange
    }
  }
}
