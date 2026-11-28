//
// EpubReadingFooterLabels.swift
//
//

#if os(iOS)
  import SwiftUI

  /// Reading-state footer labels and optional thin progress bar, hosted inside
  /// `EpubReaderBottomBar`'s persistent layout on the same baseline as the
  /// controls page counter.
  struct EpubReadingFooterLabels: View {
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
      text(for: overlayPreferences.readerFooterLeading)
    }

    private var centerText: String? {
      text(for: overlayPreferences.readerFooterCenter)
    }

    private var trailingText: String? {
      text(for: overlayPreferences.readerFooterTrailing)
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
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
            }
            if let trailingText {
              Text(trailingText)
                .lineLimit(1)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
          }
          .font(.caption)
          .foregroundStyle(theme.textColor.opacity(0.6))
          .accessibilityElement(children: .combine)
        }
      }
      .frame(maxWidth: .infinity)
      .overlay(alignment: .bottom) {
        if overlayPreferences.showsReaderProgressBar,
          let progression = viewModel.currentLocation?.totalProgression
        {
          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              Capsule()
                .fill(theme.textColor.opacity(0.18))
              Capsule()
                .fill(theme.textColor.opacity(0.85))
                .frame(width: proxy.size.width * min(max(progression, 0), 1))
            }
          }
          .scaleEffect(x: viewModel.publicationReadingProgression == .rtl ? -1 : 1, y: 1)
          .frame(height: 3)
          .offset(y: 7)
        }
      }
    }
  }
#endif
