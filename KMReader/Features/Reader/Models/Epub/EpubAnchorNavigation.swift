#if os(iOS) || os(macOS)
  import Foundation

  struct EpubAnchorNavigation: Equatable {
    let id: UUID
    let chapterIndex: Int
    let anchor: String
  }
#endif
