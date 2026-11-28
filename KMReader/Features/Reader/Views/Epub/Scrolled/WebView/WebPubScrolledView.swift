//
// WebPubScrolledView.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit
  import WebKit

  /// A SwiftUI view that displays EPUB content in continuous vertical scroll mode.
  struct WebPubScrolledView: UIViewControllerRepresentable {
    @Bindable var viewModel: EpubReaderViewModel
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let tapScrollPercentage: Double
    let animateTapTurns: Bool
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ScrolledEpubViewController {
      let chapterIndex = viewModel.currentChapterIndex
      let pageIndex = viewModel.currentPageIndex
      let theme = preferences.resolvedTheme(for: colorScheme)
      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let readiumPayload = preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        flowStyle: .scrolled,
        rootURL: viewModel.resourceRootURL,
        viewportSize: viewModel.resolvedViewportSize
      )

      let vc = ScrolledEpubViewController(
        chapterURL: viewModel.chapterURL(at: chapterIndex),
        chapterMediaType: viewModel.chapterMediaType(at: chapterIndex),
        rootURL: viewModel.resourceRootURL,
        mediaTypesByRelativePath: viewModel.mediaTypesByRelativePath,
        containerInsets: viewModel.containerInsetsForLabels().uiEdgeInsets,
        tapScrollPercentage: tapScrollPercentage,
        animateTapTurns: animateTapTurns,
        theme: theme,
        contentCSS: readiumPayload.css,
        readiumProperties: readiumPayload.properties,
        publicationLanguage: viewModel.publicationLanguage,
        publicationReadingProgression: viewModel.publicationReadingProgression,
        chapterIndex: chapterIndex,
        initialSubPageIndex: pageIndex,
        destination: viewModel.navigationRequest?.destination,
        totalChapters: viewModel.chapterCount,
        useSafeArea: viewModel.useSafeArea
      )

      vc.onCenterTap = onCenterTap
      vc.onEndReached = onEndReached
      vc.onChapterNavigationNeeded = { [weak viewModel] targetChapterIndex in
        guard let viewModel = viewModel else { return }

        viewModel.navigateToPage(
          chapterIndex: targetChapterIndex,
          pageIndex: targetChapterIndex < viewModel.currentChapterIndex ? -1 : 0
        )
      }
      vc.navigationID = viewModel.navigationID
      vc.onPageDidChange = { [weak viewModel] landing in
        viewModel?.commitPosition(landing)
      }
      vc.onPageCountReady = { [weak viewModel] chapterIndex, pageCount, navigationID in
        guard let viewModel, viewModel.navigationID == navigationID else { return }
        viewModel.updateChapterPageCount(pageCount, for: chapterIndex)
      }
      vc.onLinkTap = { [weak viewModel] url in
        viewModel?.navigateToURL(url)
      }
      vc.requiresFullExtentProvider = { [weak viewModel] chapterIndex in
        viewModel?.navigationRequiresFullExtent(for: chapterIndex) ?? false
      }
      vc.pendingAnchorProvider = { [weak viewModel] chapterIndex in
        viewModel?.pendingAnchorNavigation(for: chapterIndex)
      }

      context.coordinator.viewController = vc

      return vc
    }

    func updateUIViewController(_ uiViewController: ScrolledEpubViewController, context: Context) {
      context.coordinator.parent = self
      uiViewController.onEndReached = onEndReached

      let chapterIndex = viewModel.targetChapterIndex ?? uiViewController.currentChapterIndex
      let containerInsets = viewModel.containerInsetsForLabels().uiEdgeInsets
      let theme = preferences.resolvedTheme(for: colorScheme)

      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let readiumPayload = preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        flowStyle: .scrolled,
        rootURL: viewModel.resourceRootURL,
        viewportSize: viewModel.resolvedViewportSize
      )

      uiViewController.configure(
        chapterURL: viewModel.chapterURL(at: chapterIndex),
        chapterMediaType: viewModel.chapterMediaType(at: chapterIndex),
        rootURL: viewModel.resourceRootURL,
        mediaTypesByRelativePath: viewModel.mediaTypesByRelativePath,
        containerInsets: containerInsets,
        tapScrollPercentage: tapScrollPercentage,
        animateTapTurns: animateTapTurns,
        theme: theme,
        contentCSS: readiumPayload.css,
        readiumProperties: readiumPayload.properties,
        publicationLanguage: viewModel.publicationLanguage,
        publicationReadingProgression: viewModel.publicationReadingProgression,
        chapterIndex: chapterIndex,
        navigationID: viewModel.navigationID,
        navigationRequest: viewModel.navigationRequest,
        totalChapters: viewModel.chapterCount,
        useSafeArea: viewModel.useSafeArea
      )
    }

    class Coordinator: NSObject {
      var parent: WebPubScrolledView
      weak var viewController: ScrolledEpubViewController?

      init(_ parent: WebPubScrolledView) {
        self.parent = parent
      }
    }
  }
#endif
