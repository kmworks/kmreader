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
    let useSafeArea: Bool
  }
#endif
