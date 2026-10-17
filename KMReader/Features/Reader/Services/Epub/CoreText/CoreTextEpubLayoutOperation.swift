#if os(iOS)
  import UIKit
  import YueduCoreText

  @MainActor
  final class CoreTextEpubLayoutOperation {
    private let generation: Int
    private let document: HTMLLayoutDocument
    // YueduCoreText's loader closures are weak, so retain the loader through layout.
    private let resourceLoader: CoreTextEpubResourceLoader
    private var pageSession: BrowserLayoutSession?

    init(
      rootURL: URL,
      chapterURL: URL,
      preferences: EpubThemePreferences,
      theme: ReaderTheme,
      viewportSize: CGSize,
      publicationLanguage: String?,
      publicationReadingProgression: WebPubReadingProgression?,
      generation: Int
    ) throws {
      self.generation = generation
      let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
      resourceLoader = CoreTextEpubResourceLoader(
        rootURL: rootURL,
        chapterURL: chapterURL,
        customFontPath: fontPath
      )
      var layout = CoreTextEpubLayoutConfiguration(
        preferences: preferences,
        theme: theme,
        viewportSize: viewportSize,
        publicationLanguage: publicationLanguage,
        publicationReadingProgression: publicationReadingProgression
      )
      layout.configuration.fontResolver = resourceLoader.fontResolver
      let input = try resourceLoader.makeInput(
        userStylesheet: layout.userStylesheet, baseStylesheet: layout.baseStylesheet)
      document = HTMLLayoutDocument(
        input: input,
        configuration: layout.configuration,
        imageLoader: resourceLoader.imageLoader
      )
    }

    func makePageSession() throws -> BrowserLayoutSession {
      let session = try document.makePageSession(generation: generation)
      pageSession = session
      return session
    }

    func makeContinuousDocument() throws -> BrowserScrollDocument {
      try document.prepareContinuous().makeDocument()
    }

    func cancel() {
      pageSession?.cancel()
    }
  }
#endif
