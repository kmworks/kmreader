//
// EpubReaderTopBar.swift
//
//

#if os(iOS)
  import SwiftUI

  /// Persistent top bar in the reader's `VStack`. All children stay mounted in
  /// both reading and controls states — visibility is driven purely by opacity
  /// — so the bar's intrinsic height can never change across chrome toggles.
  struct EpubReaderTopBar: View {
    let viewModel: EpubReaderViewModel
    let incognito: Bool
    let theme: ReaderTheme
    let flowStyle: EpubFlowStyle
    let overlayPreferences: EpubOverlayPreferences
    let bookTitle: String?
    let topInset: CGFloat
    let showsControls: Bool
    @Binding var isScrubbing: Bool
    let onClose: () -> Void

    private var showsReaderControls: Bool {
      showsControls && viewModel.hasContent && !viewModel.isLoading && viewModel.errorMessage == nil
    }

    private var showsButtons: Bool {
      showsControls && !isScrubbing
    }

    private var controlsHeaderText: String? {
      WebPubInfoOverlaySupport.text(
        for: .chapterRemaining,
        flowStyle: flowStyle == .paged ? .paged : .scrolled,
        bookTitle: nil,
        chapterTitle: nil,
        totalProgression: nil,
        currentPageIndex: viewModel.currentPageIndex,
        totalPagesInChapter: viewModel.currentLocation?.pageCount ?? 0
      )
    }

    var body: some View {
      ZStack {
        HStack(spacing: 12) {
          closeButton
            .opacity(showsButtons ? 1 : 0)
            .allowsHitTesting(showsButtons)
            .accessibilityHidden(!showsButtons)

          Spacer(minLength: 0)

          if let controlsHeaderText {
            Text(controlsHeaderText)
              .font(.subheadline.weight(.medium))
              .monospacedDigit()
              .foregroundStyle(theme.textColor.opacity(0.62))
              .lineLimit(1)
              .truncationMode(.tail)
              .opacity(showsReaderControls ? 1 : 0)
              .allowsHitTesting(false)
          }

          Spacer(minLength: 0)

          trailingButton
            .opacity(showsReaderControls && !isScrubbing ? 1 : 0)
            .allowsHitTesting(showsReaderControls && !isScrubbing)
            .accessibilityHidden(!(showsReaderControls && !isScrubbing))
        }
        .opacity(showsControls ? 1 : 0)
        .offset(y: showsControls ? 0 : -12)

        EpubReadingHeaderLabels(
          viewModel: viewModel,
          theme: theme,
          flowStyle: flowStyle,
          overlayPreferences: overlayPreferences,
          bookTitle: bookTitle
        )
        .opacity(showsControls ? 0 : 1)
        .offset(y: showsControls ? -8 : 0)
        .accessibilityHidden(showsControls)
      }
      .padding(.horizontal, 16)
      .padding(.top, max(8, topInset - 4))
      .background(theme.backgroundColor)
      .allowsHitTesting(showsControls)
      .animation(.appCurve(0.24), value: showsControls)
      .animation(.appCurve(0.2), value: isScrubbing)
    }

    private var closeButton: some View {
      Button(action: onClose) {
        EpubReaderControlGlyph(systemName: AppIcon.close)
          .contentShape(Circle())
      }
      .controlSize(.regular)
      .buttonBorderShape(.circle)
      .readerControlButtonStyle()
      .accessibilityLabel(Text("Close"))
    }

    @ViewBuilder
    private var trailingButton: some View {
      if incognito {
        // Incognito reading keeps no bookmarks; the inert marker still swallows
        // its tap so the slot never falls through to a page-turn zone.
        Button {
        } label: {
          EpubReaderControlGlyph(systemName: AppIcon.peek)
            .opacity(0.6)
            .contentShape(Circle())
        }
        .controlSize(.regular)
        .buttonBorderShape(.circle)
        .readerControlButtonStyle()
        .accessibilityLabel(Text("Incognito Reading"))
        .accessibilityRemoveTraits(.isButton)
      } else {
        Button {
          HapticFeedback.selectionChanged()
          Task { await viewModel.toggleBookmark() }
        } label: {
          EpubReaderControlGlyph(systemName: AppIcon.bookmark)
            .symbolVariant(viewModel.isCurrentPositionBookmarked ? .fill : .none)
            .contentTransition(.symbolEffect(.replace, options: .nonRepeating))
            .contentShape(Circle())
        }
        .controlSize(.regular)
        .buttonBorderShape(.circle)
        .readerControlButtonStyle()
        .disabled(!viewModel.canToggleBookmark)
        .accessibilityLabel(
          viewModel.isCurrentPositionBookmarked ? Text("Remove Bookmark") : Text("Add Bookmark")
        )
      }
    }
  }
#endif
