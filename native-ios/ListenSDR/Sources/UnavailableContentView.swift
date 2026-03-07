import SwiftUI

struct UnavailableContentView: View {
  let title: String
  let systemImage: String
  let description: String

  var body: some View {
    Group {
      if #available(iOS 17.0, *) {
        ContentUnavailableView(
          title,
          systemImage: systemImage,
          description: Text(description)
        )
      } else {
        VStack(spacing: 12) {
          Image(systemName: systemImage)
            .font(.system(size: 36))
            .foregroundStyle(.secondary)

          Text(title)
            .font(.headline)

          Text(description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
      }
    }
  }
}
