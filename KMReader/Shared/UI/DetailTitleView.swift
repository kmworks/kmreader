import SwiftUI

struct DetailTitleView: View {
  let title: String

  @Environment(\.detailHeroCentered) private var heroCentered

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Text(title)
        .font(heroCentered ? Font.title2.bold() : Font.title2)
        .multilineTextAlignment(heroCentered ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .textSelectionIfAvailable()
        .layoutPriority(1)

      #if os(iOS) || os(macOS)
        Button {
          copyTitle()
        } label: {
          Image(systemName: AppIcon.copy)
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .adaptiveButtonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("Copy"))
      #endif
    }
  }

  private func copyTitle() {
    #if os(iOS) || os(macOS)
      PlatformHelper.generalPasteboard.string = title
      ErrorManager.shared.notify(message: String(localized: "notification.copied"))
    #endif
  }
}
