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
    /// Previous/next sibling in the book's series (or read list), shown as
    /// continuation cards.
    var previousBook: Book?
    var nextBook: Book?
    /// Series or read list title shown above the continuation cards.
    var relationTitle: String?
    var onOpenBook: ((Book) -> Void)?
    let onReturn: () -> Void
    let onClose: () -> Void

    private var theme: ReaderTheme {
      preferences.resolvedTheme(for: colorScheme)
    }

    var body: some View {
      ZStack {
        theme.backgroundColor
          .readerIgnoresSafeArea()

        ScrollView {
          VStack(spacing: 24) {
            Spacer(minLength: 32)

            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 60))
              .foregroundStyle(theme.textColor.opacity(0.8))

            Text("Book Finished")
              .font(.title2)
              .fontWeight(.semibold)
              .foregroundStyle(theme.textColor)

            if let bookTitle {
              Text(bookTitle)
                .font(.subheadline)
                .foregroundStyle(theme.textColor.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            if previousBook != nil || nextBook != nil {
              continuationSection
            }

            VStack(spacing: 12) {
              Button {
                onReturn()
              } label: {
                HStack {
                  Text("Return")
                    .font(.callout)
                  Image(systemName: "arrow.uturn.backward")
                }
              }
              .adaptiveButtonStyle(.bordered)
              .buttonBorderShape(.capsule)
              .tint(theme.textColor)
              .controlSize(.large)

              Button {
                onClose()
              } label: {
                HStack {
                  Text("Close")
                    .font(.callout)
                  Image(systemName: AppIcon.close)
                }
              }
              .adaptiveButtonStyle(.bordered)
              .buttonBorderShape(.capsule)
              .tint(theme.textColor)
              .controlSize(.large)
            }

            Spacer(minLength: 32)
          }
          .frame(maxWidth: .infinity)
        }
      }
    }

    @ViewBuilder
    private var continuationSection: some View {
      VStack(spacing: 12) {
        if let relationTitle {
          Text(relationTitle)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(theme.textColor.opacity(0.5))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }

        VStack(spacing: 8) {
          if let previousBook {
            continuationCard(
              book: previousBook,
              label: String(localized: "Previous Book"),
              icon: "arrow.left"
            )
          }
          if let nextBook {
            continuationCard(
              book: nextBook,
              label: String(localized: "Next Book"),
              icon: "arrow.right"
            )
          }
        }
        .padding(.horizontal, 32)
      }
    }

    @ViewBuilder
    private func continuationCard(book: Book, label: String, icon: String) -> some View {
      Button {
        onOpenBook?(book)
      } label: {
        HStack(spacing: 12) {
          ThumbnailImage(
            id: book.id,
            width: 48,
            cornerRadius: 6,
            isTransitionSource: false
          )

          VStack(alignment: .leading, spacing: 2) {
            Text(label)
              .font(.caption)
              .fontWeight(.medium)
              .foregroundStyle(theme.textColor.opacity(0.5))
            Text(book.metadata.title)
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundStyle(theme.textColor)
              .lineLimit(2)
            if !book.metadata.number.isEmpty {
              Text("#\(book.metadata.number)")
                .font(.caption2)
                .foregroundStyle(theme.textColor.opacity(0.5))
            }
          }

          Spacer(minLength: 8)

          Image(systemName: icon)
            .font(.callout)
            .foregroundStyle(theme.textColor.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(theme.textColor.opacity(0.06))
        )
      }
      .adaptiveButtonStyle(.plain)
    }
  }

  #Preview {
    EpubEndPageView(
      bookTitle: "Sample Book",
      preferences: EpubThemePreferences(),
      colorScheme: .dark,
      onReturn: {},
      onClose: {}
    )
  }
#endif
