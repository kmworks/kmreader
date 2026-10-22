import Foundation

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

enum MangaHorizontalTextLayout {
  static func fittedFontSize(
    text: String, width: CGFloat, preferredFontSize: CGFloat, targetLanguage: String
  ) -> CGFloat {
    // CJK line breaking may legitimately split a linguistic word.
    guard !MangaTranslationLanguage.supportsVerticalLayout(targetLanguage) else {
      return preferredFontSize
    }
    let text = text as NSString
    let words = wordRanges(in: text)
    guard width > 0, !words.isEmpty else { return preferredFontSize }

    var fontSize = preferredFontSize
    while fontSize > 1 {
      let font = PlatformFont.systemFont(ofSize: fontSize, weight: .medium)
      guard hasSplitWord(text, words: words, font: font, width: width) else { break }
      let longestWordWidth = words.reduce(CGFloat.zero) { result, word in
        let word = text.substring(with: word) as NSString
        return max(result, word.size(withAttributes: [.font: font]).width)
      }
      let estimatedSize =
        longestWordWidth > 0
        ? fontSize * width / longestWordWidth * 0.95
        : fontSize * 0.95
      // Glyph hinting can make the full line wrap even when word metrics fit.
      fontSize = max(1, min(fontSize * 0.95, estimatedSize))
    }
    return fontSize
  }

  private static func wordRanges(in text: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byWords) {
      _, range, _, _ in
      ranges.append(range)
    }
    return ranges
  }

  private static func hasSplitWord(
    _ text: NSString, words: [NSRange], font: PlatformFont, width: CGFloat
  ) -> Bool {
    let storage = NSTextStorage(string: text as String, attributes: [.font: font])
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: width, height: 10_000))
    container.lineFragmentPadding = 0
    container.lineBreakMode = .byWordWrapping
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)

    var glyphIndex = 0
    while glyphIndex < layout.numberOfGlyphs {
      var glyphRange = NSRange()
      _ = layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &glyphRange)
      let line = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
      let lineEnd = NSMaxRange(line)
      for word in words {
        let wordEnd = NSMaxRange(word)
        if (line.location > word.location && line.location < wordEnd)
          || (lineEnd > word.location && lineEnd < wordEnd)
        {
          return true
        }
      }
      glyphIndex = NSMaxRange(glyphRange)
    }
    return false
  }
}
