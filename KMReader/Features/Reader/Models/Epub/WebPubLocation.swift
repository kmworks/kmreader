#if os(iOS) || os(macOS)
  struct WebPubLocation: Equatable {
    let href: String
    let title: String?
    let progression: Double?
    let totalProgression: Double?
    let pageIndex: Int
    let pageCount: Int
  }
#endif
