#if os(iOS) || os(macOS)
  import Foundation

  enum WebPubPaginationLayout: String, Sendable {
    case horizontal
    case reverseHorizontal

    static func resolve(
      language: String?,
      readingProgression: WebPubReadingProgression?
    ) -> WebPubPaginationLayout {
      if readingProgression == .rtl {
        return .reverseHorizontal
      }

      switch ReadiumCSSLoader.resolveVariantSubdirectory(
        language: language,
        readingProgression: readingProgression
      ) {
      case "rtl", "cjk-vertical":
        return .reverseHorizontal
      default:
        return .horizontal
      }
    }

    var usesReverseScrollLeft: Bool {
      self == .reverseHorizontal
    }

    var reversesHorizontalGestureDirection: Bool {
      self == .reverseHorizontal
    }
  }
#endif
