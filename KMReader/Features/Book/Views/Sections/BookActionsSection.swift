//
// BookActionsSection.swift
//
//

import SwiftUI

/// The book detail page's action block: a prominent capsule Read button
/// filling the action card, carrying the action label over a page/progress
/// detail line like the series continue-reading button, then Peek and the
/// download toggle as a secondary row. Alignment follows
/// `detailHeroCentered`. Series navigation lives on the hero's series title
/// instead of a button here.
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

  private var readDetail: Text {
    if let progress = book.readProgress, book.isInProgress {
      guard book.media.pagesCount > 0 else {
        return Text("Page \(progress.page)")
      }
      let value = min(max(Double(progress.page) / Double(book.media.pagesCount), 0), 1)
      return Text("Page \(progress.page)") + Text(verbatim: " · ")
        + Text(value, format: .percent.precision(.fractionLength(0)))
    }
    if book.media.pagesCount > 0 {
      return Text("\(book.media.pagesCount) pages")
    }
    return Text(book.media.statusValue.label)
  }

  var body: some View {
    VStack(alignment: heroCentered ? .center : .leading, spacing: 8) {
      Button {
        readerActions.open(book: book, incognito: false)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "book.fill")
            .font(.callout)

          VStack(alignment: .leading, spacing: 1) {
            Text(readLabel)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
              .contentTransition(.opacity)

            readDetail
              .font(.caption)
              .opacity(0.85)
              .lineLimit(1)
              .contentTransition(.opacity)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
      }
      .adaptiveButtonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)

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
    .animation(.appCurve(), value: downloadStatus)
    .animation(.appCurve(), value: book.readProgress)
  }
}
