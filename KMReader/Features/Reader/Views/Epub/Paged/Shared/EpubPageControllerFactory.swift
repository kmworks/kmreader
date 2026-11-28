#if os(iOS)
  import SwiftUI
  import UIKit

  @MainActor
  struct EpubPageControllerFactory {
    let viewModel: EpubReaderViewModel
    let renderingEngine: EpubRenderingEngine
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme

    func makeController(
      chapterIndex: Int,
      subPageIndex: Int,
      preferLastPageOnReady: Bool
    ) -> EpubPageViewController? {
      guard chapterIndex >= 0, chapterIndex < viewModel.chapterCount else { return nil }
      let pageCount = viewModel.chapterPageCount(at: chapterIndex) ?? 1
      if !preferLastPageOnReady {
        guard subPageIndex >= 0, subPageIndex < pageCount else { return nil }
      } else {
        guard subPageIndex >= 0 else { return nil }
      }

      let containerInsets = viewModel.containerInsetsForLabels().uiEdgeInsets
      let theme = preferences.resolvedTheme(for: colorScheme)
      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let chapterURL = viewModel.chapterURL(at: chapterIndex)
      let chapterMediaType = viewModel.chapterMediaType(at: chapterIndex)
      let rootURL = viewModel.resourceRootURL
      let readiumPayload = preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        rootURL: rootURL,
        viewportSize: viewModel.resolvedViewportSize
      )
      let onPageCountReady = pageCountCallback(chapterIndex: chapterIndex)

      let locationPageIndex = min(max(subPageIndex, 0), max(0, pageCount - 1))
      guard viewModel.pageLocation(chapterIndex: chapterIndex, pageIndex: locationPageIndex) != nil else {
        return nil
      }

      let configuration = EpubChapterConfiguration(
        preferences: preferences,
        chapterURL: chapterURL,
        chapterMediaType: chapterMediaType,
        rootURL: rootURL,
        mediaTypesByRelativePath: viewModel.mediaTypesByRelativePath,
        containerInsets: containerInsets,
        theme: theme,
        contentCSS: readiumPayload.css,
        readiumProperties: readiumPayload.properties,
        publicationLanguage: viewModel.publicationLanguage,
        publicationReadingProgression: viewModel.publicationReadingProgression,
        chapterIndex: chapterIndex,
        subPageIndex: subPageIndex,
        totalPages: pageCount,
        useSafeArea: viewModel.useSafeArea
      )
      let controller = EpubPageViewController(
        configuration: configuration,
        renderingEngine: renderingEngine,
        onPageCountReady: onPageCountReady
      )
      controller.navigationIsCurrent = { [weak viewModel] navigationID in
        viewModel?.navigationID == navigationID
      }
      controller.prepareNavigation(
        viewModel.navigationRequest.flatMap { $0.chapterIndex == chapterIndex ? $0 : nil }
          ?? EpubNavigationRequest(
            id: viewModel.navigationID, chapterIndex: chapterIndex,
            destination: preferLastPageOnReady ? .lastPage : .page(subPageIndex)
          )
      )
      controller.requiresFullExtentProvider = { [weak viewModel] chapterIndex in
        viewModel?.navigationRequiresFullExtent(for: chapterIndex) ?? false
      }
      controller.onChapterLoadFailed = { [weak viewModel] in
        viewModel?.markChapterLoadFailed(chapterIndex)
      }
      return controller
    }

    func reconfigure(_ controller: EpubPageViewController) {
      let chapterIndex = controller.chapterIndex
      let containerInsets = viewModel.containerInsetsForLabels().uiEdgeInsets
      let theme = preferences.resolvedTheme(for: colorScheme)
      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      let readiumPayload = preferences.makeReadiumPayload(
        theme: theme,
        fontPath: fontPath,
        rootURL: viewModel.resourceRootURL,
        viewportSize: viewModel.resolvedViewportSize
      )

      let configuration = EpubChapterConfiguration(
        preferences: preferences,
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
        chapterIndex: chapterIndex,
        subPageIndex: controller.currentSubPageIndex,
        totalPages: controller.totalPagesInChapter,
        useSafeArea: viewModel.useSafeArea
      )
      controller.configure(
        configuration,
        onPageCountReady: pageCountCallback(chapterIndex: chapterIndex)
      )
    }

    func prepareNavigation(on controller: EpubPageViewController) {
      let chapterIndex = controller.chapterIndex
      if viewModel.targetChapterIndex == nil || viewModel.targetChapterIndex == chapterIndex {
        controller.prepareNavigation(
          viewModel.navigationRequest
            ?? EpubNavigationRequest(
              id: viewModel.navigationID, chapterIndex: chapterIndex,
              destination: .page(controller.currentSubPageIndex)
            )
        )
      }
    }

    private func pageCountCallback(chapterIndex: Int) -> (Int) -> Void {
      let chapterIndexForCallback = chapterIndex
      return { [weak viewModel] pageCount in
        viewModel?.updateChapterPageCount(pageCount, for: chapterIndexForCallback)
      }
    }
  }
#endif
