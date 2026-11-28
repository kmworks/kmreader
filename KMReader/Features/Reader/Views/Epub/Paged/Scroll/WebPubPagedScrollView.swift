//
// WebPubPagedScrollView.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit
  import WebKit

  /// A SwiftUI view that displays EPUB content in paged mode with swipe scrolling.
  /// Uses a single WKWebView and horizontal pagination.
  struct WebPubPagedScrollView: UIViewControllerRepresentable {
    @Bindable var viewModel: EpubReaderViewModel
    let animatePageTransitions: Bool
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PagedScrollEpubViewController {
      let chapterIndex = viewModel.currentChapterIndex
      let pageIndex = viewModel.currentPageIndex
      let theme = preferences.resolvedTheme(for: colorScheme)
      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let readiumPayload = preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        rootURL: viewModel.resourceRootURL,
        viewportSize: viewModel.resolvedViewportSize
      )

      let vc = PagedScrollEpubViewController(
        chapterURL: viewModel.chapterURL(at: chapterIndex),
        chapterMediaType: viewModel.chapterMediaType(at: chapterIndex),
        rootURL: viewModel.resourceRootURL,
        mediaTypesByRelativePath: viewModel.mediaTypesByRelativePath,
        containerInsets: viewModel.containerInsetsForLabels().uiEdgeInsets,
        theme: theme,
        contentCSS: readiumPayload.css,
        readiumProperties: readiumPayload.properties,
        publicationLanguage: viewModel.publicationLanguage,
        publicationReadingProgression: viewModel.publicationReadingProgression,
        animatePageTransitions: animatePageTransitions,
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

    func updateUIViewController(_ uiViewController: PagedScrollEpubViewController, context: Context) {
      context.coordinator.parent = self
      uiViewController.onEndReached = onEndReached

      let chapterIndex = viewModel.targetChapterIndex ?? uiViewController.currentChapterIndex
      let pageIndex =
        chapterIndex == viewModel.currentChapterIndex
        ? viewModel.currentPageIndex : uiViewController.currentPageIndex
      let containerInsets = viewModel.containerInsetsForLabels().uiEdgeInsets
      let theme = preferences.resolvedTheme(for: colorScheme)

      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let readiumPayload = preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        rootURL: viewModel.resourceRootURL,
        viewportSize: viewModel.resolvedViewportSize
      )

      uiViewController.configure(
        chapterURL: viewModel.chapterURL(at: chapterIndex),
        chapterMediaType: viewModel.chapterMediaType(at: chapterIndex),
        rootURL: viewModel.resourceRootURL,
        mediaTypesByRelativePath: viewModel.mediaTypesByRelativePath,
        containerInsets: containerInsets,
        theme: theme,
        contentCSS: readiumPayload.css,
        readiumProperties: readiumPayload.properties,
        publicationLanguage: viewModel.publicationLanguage,
        publicationReadingProgression: viewModel.publicationReadingProgression,
        animatePageTransitions: animatePageTransitions,
        chapterIndex: chapterIndex,
        navigationID: viewModel.navigationID,
        navigationRequest: viewModel.navigationRequest,
        totalChapters: viewModel.chapterCount,
        useSafeArea: viewModel.useSafeArea
      )
    }

    class Coordinator: NSObject {
      var parent: WebPubPagedScrollView
      weak var viewController: PagedScrollEpubViewController?

      init(_ parent: WebPubPagedScrollView) {
        self.parent = parent
      }
    }
  }
#endif
