//
// BookActionsSection.swift
//
//

import SwiftUI

/// The book detail page's action block: a prominent capsule Read button —
/// full width in centered layouts, a fixed wide width when leading — then
/// Peek and the download toggle as a secondary row. Pages/progress stay
/// in the status row above, so the button carries the action label only.
/// Alignment follows `detailHeroCentered`. Series navigation lives on the
/// hero's series title instead of a button here.
struct BookActionsSection: View {
  let book: Book
  let downloadStatus: DownloadStatus?

  @Environment(\.readerActions) private var readerActions
  @Environment(\.detailHeroCentered) private var heroCentered
  @AppStorage("currentAccount") private var current: Current = .init()

  private var readLabel: String {
    if book.hasStartedReading && !book.isCompleted {
      return String(localized: "Resume Reading")
    } else {
      return String(localized: "Start Reading")
    }
  }

  var body: some View {
    VStack(alignment: heroCentered ? .center : .leading, spacing: 8) {
      Button {
        readerActions.open(book: book, incognito: false)
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "book.fill")
            .font(.subheadline)

          Text(readLabel)
            .font(.subheadline)
        }
        .frame(maxWidth: heroCentered ? .infinity : 480)
        .padding(.horizontal, 12)
      }
      .adaptiveButtonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .controlSize(.small)

      HStack {
        Button {
          readerActions.open(book: book, incognito: true)
        } label: {
          Label("Peek", systemImage: "eye.slash")
        }
        .adaptiveButtonStyle(.bordered)

        if let downloadStatus {
          Button {
            Task {
              await OfflineManager.shared.toggleDownload(
                instanceId: current.instanceId, info: book.downloadInfo)
            }
          } label: {
            HStack(spacing: 4) {
              Image(systemName: downloadStatus.menuIcon)
                .font(.caption2)
              Text(downloadStatus.menuLabel)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            }
          }
          .adaptiveButtonStyle(.bordered)
          .optimizedControlSize()
          .tint(downloadStatus.menuColor)
        }
      }
      .font(.caption)
      .buttonBorderShape(.capsule)
    }
    .frame(maxWidth: .infinity, alignment: heroCentered ? .center : .leading)
    .animation(.default, value: downloadStatus)
  }
}
