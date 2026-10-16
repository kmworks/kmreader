#if os(iOS)
  import SwiftUI
  import UIKit
  import YueduCoreText

  struct CoreTextScrolledEpubView: UIViewControllerRepresentable {
    @Bindable var viewModel: EpubReaderViewModel
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let tapScrollPercentage: Double
    let animateTapTurns: Bool
    let overlayPreferences: EpubOverlayPreferences
    let showingControls: Bool
    let bookTitle: String?
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    @AppStorage("epubTapZoneMode") private var tapZoneMode: TapZoneMode = AppConfig.epubTapZoneMode
    @AppStorage("epubTapZoneInversionMode") private var tapZoneInversionMode: TapZoneInversionMode = AppConfig
      .epubTapZoneInversionMode

    func makeUIViewController(context: Context) -> CoreTextScrolledEpubViewController {
      CoreTextScrolledEpubViewController(
        viewModel: viewModel,
        preferences: preferences,
        colorScheme: colorScheme,
        tapScrollPercentage: tapScrollPercentage,
        animateTapTurns: animateTapTurns,
        overlayPreferences: overlayPreferences,
        showingControls: showingControls,
        bookTitle: bookTitle,
        onCenterTap: onCenterTap,
        onEndReached: onEndReached,
        tapZoneMode: tapZoneMode,
        tapZoneInversionMode: tapZoneInversionMode
      )
    }

    func updateUIViewController(_ uiViewController: CoreTextScrolledEpubViewController, context: Context) {
      uiViewController.configure(
        preferences: preferences,
        colorScheme: colorScheme,
        tapScrollPercentage: tapScrollPercentage,
        animateTapTurns: animateTapTurns,
        overlayPreferences: overlayPreferences,
        showingControls: showingControls,
        bookTitle: bookTitle,
        onCenterTap: onCenterTap,
        onEndReached: onEndReached,
        tapZoneMode: tapZoneMode,
        tapZoneInversionMode: tapZoneInversionMode
      )
    }
  }
#endif
