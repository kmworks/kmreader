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
    let overlayPreferences: EpubOverlayPreferences
    let showingControls: Bool
    let bookTitle: String?
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PagedScrollEpubViewController {
      let chapterIndex = viewModel.currentChapterIndex
      let pageIndex = viewModel.currentPageIndex
      let currentLocation = viewModel.pageLocation(chapterIndex: chapterIndex, pageIndex: pageIndex)
      let initialProgression = viewModel.requestedProgression(for: chapterIndex)

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
        targetProgressionOnReady: initialProgression,
        totalChapters: viewModel.chapterCount,
        bookTitle: bookTitle,
        chapterTitle: currentLocation?.title,
        totalProgression: currentLocation.flatMap { location in
          viewModel.totalProgression(
            location: location,
            chapterProgress: nil
          )
        },
        overlayPreferences: overlayPreferences,
        showingControls: showingControls,
        labelTopOffset: viewModel.labelTopOffset,
        labelBottomOffset: viewModel.labelBottomOffset,
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
      vc.onPageDidChange = { [weak viewModel] chapterIndex, pageIndex, navigationID in
        viewModel?.commitScrollPosition(chapterIndex: chapterIndex, pageIndex: pageIndex, navigationID: navigationID)
      }
      vc.onPageCountReady = { [weak viewModel] chapterIndex, pageCount, navigationID in
        guard let viewModel, viewModel.navigationID == navigationID else { return }
        viewModel.updateChapterPageCount(pageCount, for: chapterIndex)
      }
      vc.onLinkTap = { [weak viewModel] url in
        viewModel?.navigateToURL(url)
      }
      vc.onAnchorJump = { [weak viewModel] originPage in
        guard let viewModel = viewModel else { return }
        viewModel.pushLinkBack(
          chapterIndex: viewModel.currentChapterIndex,
          pageIndex: originPage
        )
      }
      vc.requiresFullExtentProvider = { [weak viewModel] chapterIndex in
        viewModel?.navigationRequiresFullExtent(for: chapterIndex) ?? false
      }
      vc.pendingAnchorProvider = { [weak viewModel] chapterIndex in
        viewModel?.pendingAnchorNavigation(for: chapterIndex)
      }
      vc.onPendingAnchorLanding = { [weak viewModel] navigation in
        viewModel?.acknowledgeAnchorNavigation(navigation) ?? false
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
      let currentLocation = viewModel.pageLocation(chapterIndex: chapterIndex, pageIndex: pageIndex)

      let containerInsets = viewModel.containerInsetsForLabels().uiEdgeInsets
      let theme = preferences.resolvedTheme(for: colorScheme)

      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let readiumPayload = preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        rootURL: viewModel.resourceRootURL,
        viewportSize: viewModel.resolvedViewportSize
      )

      let chapterProgress =
        currentLocation?.pageCount ?? 0 > 0
        ? Double((currentLocation?.pageIndex ?? 0) + 1) / Double(currentLocation?.pageCount ?? 1)
        : nil
      let totalProgression = currentLocation.flatMap { location in
        viewModel.totalProgression(
          location: location,
          chapterProgress: chapterProgress
        )
      }

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
        targetPageIndex: viewModel.targetPageIndex,
        targetProgression: viewModel.requestedProgression(for: chapterIndex),
        totalChapters: viewModel.chapterCount,
        bookTitle: bookTitle,
        chapterTitle: currentLocation?.title,
        totalProgression: totalProgression,
        overlayPreferences: overlayPreferences,
        showingControls: showingControls,
        labelTopOffset: viewModel.labelTopOffset,
        labelBottomOffset: viewModel.labelBottomOffset,
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
