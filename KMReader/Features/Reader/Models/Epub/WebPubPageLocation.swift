#if os(iOS) || os(macOS)
  import Foundation

  struct WebPubPageLocation: Equatable {
    let href: String
    let title: String?
    let type: String?
    let chapterIndex: Int
    let pageIndex: Int
    let pageCount: Int
    let url: URL
  }
#endif
