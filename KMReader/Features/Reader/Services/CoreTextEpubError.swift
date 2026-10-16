#if os(iOS)
  import Foundation
  import YueduCoreText

  enum CoreTextEpubError {
    static func message(for error: Error) -> String {
      switch error {
      case HTMLLayoutError.unsupported(let features):
        let names = features.map(\.description).joined(separator: ", ")
        return String(localized: "Core Text cannot render this EPUB chapter's layout: \(names)")
      case HTMLLayoutError.resourceFailure(let source):
        return String(localized: "Core Text could not load an EPUB resource: \(source)")
      case HTMLLayoutError.layoutFailure(let message):
        return String(localized: "Core Text failed to lay out this EPUB chapter: \(message)")
      case HTMLLayoutError.cancelled:
        return ""
      default:
        return error.diagnosticDescription
      }
    }
  }
#endif
