//
// EpubReadingHeaderLabels.swift
//
//

#if os(iOS)
  import SwiftUI

  /// Reading-state header labels, hosted inside `EpubReaderTopBar`'s persistent
  /// layout so toggling controls only changes opacity, never layout height.
  struct EpubReadingHeaderLabels: View {
    let viewModel: EpubReaderViewModel
    let theme: ReaderTheme
    let flowStyle: EpubFlowStyle
    let overlayPreferences: EpubOverlayPreferences
    let bookTitle: String?

    private func text(for item: EpubOverlayTextItem) -> String? {
      WebPubInfoOverlaySupport.text(
        for: item,
        flowStyle: flowStyle == .paged ? .paged : .scrolled,
        bookTitle: bookTitle,
        chapterTitle: viewModel.currentLocation?.title,
        totalProgression: viewModel.currentLocation?.totalProgression,
        currentPageIndex: viewModel.currentPageIndex,
        totalPagesInChapter: viewModel.currentLocation?.pageCount ?? 0,
        bookPage: viewModel.bookPageProgress?.currentPage,
        totalBookPages: viewModel.bookPageProgress?.totalPages
      )
    }

    private var leadingText: String? {
      text(for: overlayPreferences.readerHeaderLeading)
    }

    private var centerText: String? {
      text(for: overlayPreferences.readerHeaderCenter)
    }

    private var trailingText: String? {
      text(for: overlayPreferences.readerHeaderTrailing)
    }

    private var hasLabels: Bool {
      leadingText != nil || centerText != nil || trailingText != nil
    }

    var body: some View {
      Group {
        if hasLabels {
          HStack(spacing: 8) {
            if let leadingText {
              Text(leadingText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let centerText {
              Text(centerText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            if let trailingText {
              Text(trailingText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
          }
          .font(.footnote)
          .foregroundStyle(theme.textColor.opacity(0.6))
          .accessibilityElement(children: .combine)
        }
      }
    }
  }
#endif
