#if os(iOS)
  import SwiftUI
  import UIKit
  import YueduCoreText

  struct CoreTextPagedEpubView: UIViewControllerRepresentable {
    @Bindable var viewModel: EpubReaderViewModel
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let animatePageTransitions: Bool
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    @AppStorage("epubTapZoneMode") private var tapZoneMode: TapZoneMode = AppConfig.epubTapZoneMode
    @AppStorage("epubTapZoneInversionMode") private var tapZoneInversionMode: TapZoneInversionMode = AppConfig
      .epubTapZoneInversionMode

    func makeUIViewController(context: Context) -> CoreTextPagedEpubViewController {
      let controller = CoreTextPagedEpubViewController(
        viewModel: viewModel,
        preferences: preferences,
        colorScheme: colorScheme,
        animatePageTransitions: animatePageTransitions,
        onCenterTap: onCenterTap,
        onEndReached: onEndReached,
        tapZoneMode: tapZoneMode,
        tapZoneInversionMode: tapZoneInversionMode
      )
      return controller
    }

    func updateUIViewController(_ uiViewController: CoreTextPagedEpubViewController, context: Context) {
      uiViewController.configure(
        preferences: preferences,
        colorScheme: colorScheme,
        animatePageTransitions: animatePageTransitions,
        onCenterTap: onCenterTap,
        onEndReached: onEndReached,
        tapZoneMode: tapZoneMode,
        tapZoneInversionMode: tapZoneInversionMode
      )
    }
  }
#endif
