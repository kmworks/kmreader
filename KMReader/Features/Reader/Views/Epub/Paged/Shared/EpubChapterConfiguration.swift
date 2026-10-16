#if os(iOS)
  import UIKit

  struct EpubChapterConfiguration {
    let preferences: EpubThemePreferences
    let chapterURL: URL?
    let chapterMediaType: String?
    let rootURL: URL?
    let mediaTypesByRelativePath: [String: String]
    let containerInsets: UIEdgeInsets
    let theme: ReaderTheme
    let contentCSS: String
    let readiumProperties: [String: String?]
    let publicationLanguage: String?
    let publicationReadingProgression: WebPubReadingProgression?
    let chapterIndex: Int
    let subPageIndex: Int
    let totalPages: Int
    let bookTitle: String?
    let chapterTitle: String?
    let totalProgression: Double?
    let overlayPreferences: EpubOverlayPreferences
    let showingControls: Bool
    let labelTopOffset: CGFloat
    let labelBottomOffset: CGFloat
    let useSafeArea: Bool
  }
#endif
