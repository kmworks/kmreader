#if os(iOS) || os(macOS)
  import Foundation

  struct PdfSearchResult: Identifiable, Hashable {
    let id: String
    let pageNumber: Int
    let snippet: String
  }
#endif
