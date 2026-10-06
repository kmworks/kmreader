//
// EpubEndPageView.swift
//
//

#if os(iOS) || os(macOS)
  import SwiftUI

  struct EpubEndPageView: View {
    let bookTitle: String?
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let onReturn: () -> Void
    let onClose: () -> Void

    private var theme: ReaderTheme {
      preferences.resolvedTheme(for: colorScheme)
    }

    var body: some View {
      ZStack {
        theme.backgroundColor
          .readerIgnoresSafeArea()

        VStack(spacing: 24) {
          Spacer()

          // Content section
          VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 64))
              .foregroundColor(theme.textColor)

            VStack(spacing: 8) {
              Text("Book Finished")
                .font(.title)
                .fontDesign(.rounded)
                .fontWeight(.bold)
                .foregroundColor(theme.textColor)

              if let title = bookTitle {
                Text(title)
                  .font(.body)
                  .fontDesign(.serif)
                  .foregroundColor(theme.textColor.opacity(0.7))
                  .multilineTextAlignment(.center)
                  .lineLimit(2)
                  .padding(.horizontal, 24)
              }
            }
          }
          .padding(.vertical, 40)

          Spacer()

          // Buttons section
          HStack(spacing: 16) {
            Button {
              onReturn()
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "arrow.left")
                Text("Return")
              }
              .padding(.horizontal, 4)
              .contentShape(.capsule)
            }
            .adaptiveButtonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(theme.textColor)

            Button {
              onClose()
            } label: {
              HStack(spacing: 8) {
                Image(systemName: AppIcon.close)
                Text("Close")
              }
              .padding(.horizontal, 4)
              .contentShape(.capsule)
            }
            .adaptiveButtonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(theme.textColor)
          }
        }
        .padding(40)
      }
    }
  }
#endif
