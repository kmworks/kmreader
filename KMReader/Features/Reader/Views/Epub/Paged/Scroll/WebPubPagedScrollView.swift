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
      let initialProgression = viewModel.initialProgression(for: chapterIndex)

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

        // Determine if we're going forward or backward
        let currentChapterIndex = viewModel.currentChapterIndex
        let isGoingBackward = targetChapterIndex < currentChapterIndex

        if isGoingBackward {
          // Going to previous chapter - jump to last page
          viewModel.targetChapterIndex = targetChapterIndex
          viewModel.targetPageIndex = -1
        } else {
          // Going to next chapter - jump to first page
          viewModel.targetChapterIndex = targetChapterIndex
          viewModel.targetPageIndex = 0
        }
      }
      vc.onPageDidChange = { [weak viewModel] chapterIndex, pageIndex in
        guard let viewModel = viewModel else { return }
        let normalizedPageIndex = max(0, pageIndex)
        viewModel.currentChapterIndex = chapterIndex
        viewModel.currentPageIndex = normalizedPageIndex
        let pageCount = viewModel.chapterPageCount(at: chapterIndex) ?? 1
        if normalizedPageIndex >= pageCount {
          viewModel.updateChapterPageCount(normalizedPageIndex + 1, for: chapterIndex)
        }
        viewModel.pageDidChange()
      }
      vc.onPageCountReady = { [weak viewModel] chapterIndex, pageCount in
        Task { @MainActor in
          viewModel?.updateChapterPageCount(pageCount, for: chapterIndex)
        }
      }
      context.coordinator.viewController = vc

      return vc
    }

    func updateUIViewController(_ uiViewController: PagedScrollEpubViewController, context: Context) {
      context.coordinator.parent = self
      uiViewController.onEndReached = onEndReached

      // Handle TOC navigation via targetPageIndex
      if let targetChapterIndex = viewModel.targetChapterIndex,
        let targetPageIndex = viewModel.targetPageIndex,
        targetChapterIndex >= 0,
        targetChapterIndex < viewModel.chapterCount
      {
        let uiChapterIndex = uiViewController.currentChapterIndex
        let uiPageIndex = uiViewController.currentPageIndex
        let pageCount = viewModel.chapterPageCount(at: targetChapterIndex) ?? 1
        let isLastPageRequest = targetPageIndex < 0
        let normalizedPageIndex =
          isLastPageRequest
          ? max(0, pageCount - 1)
          : max(0, min(targetPageIndex, pageCount - 1))
        let shouldNavigate =
          targetChapterIndex != uiChapterIndex
          || normalizedPageIndex != uiPageIndex

        if shouldNavigate {
          // Check if this is a jump to the last page of a chapter (backward navigation)
          let isGoingBackward = targetChapterIndex < uiChapterIndex
          let isLastPageOfChapter = isLastPageRequest || normalizedPageIndex == max(0, pageCount - 1)

          // A cross-chapter target right after load is the restore jump; hand
          // it the pending restore progression so it lands on the saved page.
          // Consumed once, so later user-initiated jumps get nil.
          if targetChapterIndex != uiChapterIndex {
            uiViewController.targetProgressionOnReady = viewModel.initialProgression(
              for: targetChapterIndex)
          }

          // Navigate to target chapter and page
          uiViewController.navigateToPage(
            chapterIndex: targetChapterIndex,
            subPageIndex: normalizedPageIndex,
            jumpToLastPage: isGoingBackward && isLastPageOfChapter
          )

          // Clear targetPageIndex and update current page
          Task { @MainActor in
            viewModel.currentChapterIndex = targetChapterIndex
            viewModel.currentPageIndex = normalizedPageIndex
            viewModel.targetChapterIndex = nil
            viewModel.targetPageIndex = nil
            viewModel.pageDidChange()
          }
          return
        }

        Task { @MainActor in
          if viewModel.currentChapterIndex != targetChapterIndex
            || viewModel.currentPageIndex != normalizedPageIndex
          {
            viewModel.currentChapterIndex = targetChapterIndex
            viewModel.currentPageIndex = normalizedPageIndex
            viewModel.pageDidChange()
          }
          viewModel.targetChapterIndex = nil
          viewModel.targetPageIndex = nil
        }
      }

      let chapterIndex = viewModel.currentChapterIndex
      let pageIndex = viewModel.currentPageIndex
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
