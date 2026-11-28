//
// EpubReaderBottomBar.swift
//
//

#if os(iOS)
  import SwiftUI

  /// Persistent bottom bar in the reader's `VStack`. The corner buttons,
  /// progress scrubber, and reading footer labels all stay mounted in one
  /// bottom-aligned `ZStack` and swap via opacity, keeping the bar height —
  /// and therefore the EPUB pagination viewport — constant by construction.
  struct EpubReaderBottomBar: View {
    let viewModel: EpubReaderViewModel
    let theme: ReaderTheme
    let flowStyle: EpubFlowStyle
    let overlayPreferences: EpubOverlayPreferences
    let bookTitle: String?
    let bottomInset: CGFloat
    let showsControls: Bool

    @Binding var showingChapterSheet: Bool
    @Binding var showingThemeSheet: Bool
    @Binding var showingSettingsSheet: Bool
    @Binding var showingDetailSheet: Bool
    @Binding var isScrubbing: Bool

    @State private var cornerButtonWidth: CGFloat = 0

    private static let horizontalPadding: CGFloat = 16
    private static let scrubberButtonGap: CGFloat = 16
    private static let centerLabelLift: CGFloat = 4

    var body: some View {
      ZStack(alignment: .bottom) {
        EpubProgressScrubberView(
          viewModel: viewModel,
          theme: theme,
          restingHorizontalInset: cornerButtonWidth > 0
            ? cornerButtonWidth + Self.scrubberButtonGap : 64,
          isScrubbing: $isScrubbing
        )
        .padding(.bottom, Self.centerLabelLift)
        .opacity(showsControls ? 1 : 0)
        .allowsHitTesting(showsControls)
        .accessibilityHidden(!showsControls)

        EpubReadingFooterLabels(
          viewModel: viewModel,
          theme: theme,
          flowStyle: flowStyle,
          overlayPreferences: overlayPreferences,
          bookTitle: bookTitle
        )
        .padding(.bottom, Self.centerLabelLift)
        .opacity(showsControls ? 0 : 1)
        .offset(y: showsControls ? -8 : 0)
        .accessibilityHidden(showsControls)

        HStack {
          returnButton
          Spacer(minLength: 0)
          moreMenu
        }
        .opacity(showsControls && !isScrubbing ? 1 : 0)
        .offset(y: showsControls ? 0 : 12)
        .allowsHitTesting(showsControls && !isScrubbing)
        .accessibilityHidden(!(showsControls && !isScrubbing))
      }
      .padding(.horizontal, Self.horizontalPadding)
      .padding(.bottom, max(8, bottomInset - 4))
      .background(theme.backgroundColor)
      .animation(.appCurve(0.24), value: showsControls)
      .animation(.appCurve(0.2), value: isScrubbing)
    }

    private var returnButton: some View {
      let canReturn = viewModel.canReturnToPreviousPosition
      return Button {
        HapticFeedback.light()
        viewModel.returnToPreviousPosition()
      } label: {
        EpubReaderControlGlyph(systemName: AppIcon.returnToPrevious)
          .contentShape(Circle())
      }
      .controlSize(.regular)
      .buttonBorderShape(.circle)
      .readerControlButtonStyle()
      .opacity(canReturn ? 1 : 0)
      .scaleEffect(canReturn ? 1 : 0.5)
      .allowsHitTesting(canReturn)
      .accessibilityHidden(!canReturn)
      .accessibilityLabel(Text("Return to previous position"))
      .animation(.appSpring, value: canReturn)
    }

    private var moreMenu: some View {
      Menu {
        menuContent()
      } label: {
        EpubReaderControlGlyph(systemName: AppIcon.more)
          .contentShape(Circle())
      }
      .menuStyle(.button)
      .menuIndicator(.hidden)
      .controlSize(.regular)
      .buttonBorderShape(.circle)
      .readerControlButtonStyle()
      .accessibilityLabel(Text("Current Reading Options"))
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: { newWidth in
        guard newWidth > 0 else { return }
        cornerButtonWidth = newWidth
      }
    }
  }
#endif
