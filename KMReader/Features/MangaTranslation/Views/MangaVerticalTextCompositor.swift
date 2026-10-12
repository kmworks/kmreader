import CoreText
import Foundation

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

nonisolated enum MangaVerticalTextCompositor {
  private static var frameAttributes: CFDictionary {
    [
      kCTFrameProgressionAttributeName: NSNumber(value: CTFrameProgression.rightToLeft.rawValue)
    ] as CFDictionary
  }

  // Model output occasionally mixes half-width punctuation into CJK text;
  // normalize the common ones to their full-width forms. Multi-char tokens
  // must be replaced before the single-character maps below run.
  private static let halfwidthTokens: [(String, String)] = [
    ("...", "…"),
    ("--", "—"),
  ]
  private static let halfwidthPunctuation: [Character: Character] = [
    "!": "！",
    "?": "？",
    "~": "〜",
  ]

  // SF covers dashes/ellipsis but has no vertical glyphs for them, so they
  // would render sideways; swap in the Unicode vertical presentation forms,
  // which fall back to a CJK font like the rest of the text. Tilde-likes all
  // normalize to the wave dash U+301C; curly quotes map to the corner-style
  // forms of vertical CJK typesetting.
  private static let verticalPresentationForms: [Character: Character] = [
    "—": "︱",  // U+2014 EM DASH
    "―": "︱",  // U+2015 HORIZONTAL BAR
    "–": "︲",  // U+2013 EN DASH
    "…": "︙",  // U+2026 HORIZONTAL ELLIPSIS
    "‥": "︰",  // U+2025 TWO DOT LEADER
    "～": "〜",  // U+FF5E FULLWIDTH TILDE
    "∼": "〜",  // U+223C TILDE OPERATOR
    "˜": "〜",  // U+02DC SMALL TILDE
    "⁓": "〜",  // U+2053 SWUNG DASH
    "〰": "〜",  // U+3030 WAVY DASH
    "“": "﹃",  // U+201C LEFT DOUBLE QUOTATION MARK
    "”": "﹄",  // U+201D RIGHT DOUBLE QUOTATION MARK
    "‘": "﹁",  // U+2018 LEFT SINGLE QUOTATION MARK
    "’": "﹂",  // U+2019 RIGHT SINGLE QUOTATION MARK
  ]

  // Consecutive CJK exclamation/question marks are conventionally typeset in a
  // single character cell; swap each pair for its precomposed one-cell form.
  // ⁉ and ‼ are emoji-capable and iOS picks the color emoji font for them,
  // so VS15 forces text presentation — also when the model emits the marks
  // directly, in bare or VS16 (emoji-style) form.
  private static let oneCellPairs: [(String, String)] = [
    ("！？", "\u{2049}\u{FE0E}"),  // EXCLAMATION QUESTION MARK
    ("？！", "\u{2048}"),  // QUESTION EXCLAMATION MARK
    ("！！", "\u{203C}\u{FE0E}"),  // DOUBLE EXCLAMATION MARK
    ("？？", "\u{2047}"),  // DOUBLE QUESTION MARK
  ]
  private static let emojiCapableMarks: [Character: Character] = [
    "\u{203C}": "\u{203C}\u{FE0E}",  // DOUBLE EXCLAMATION MARK
    "\u{2049}": "\u{2049}\u{FE0E}",  // EXCLAMATION QUESTION MARK
    "\u{203C}\u{FE0F}": "\u{203C}\u{FE0E}",  // VS16 emoji-style → VS15 text-style
    "\u{2049}\u{FE0F}": "\u{2049}\u{FE0E}",
  ]

  private static func attributedText(_ text: String, font: CTFont, color: CGColor) -> NSAttributedString {
    var text = text
    for (token, fullwidth) in halfwidthTokens {
      text = text.replacingOccurrences(of: token, with: fullwidth)
    }
    var mapped = ""
    mapped.reserveCapacity(text.count)
    var previous: Character?
    for ch in text {
      // ’ doubles as the English apostrophe; convert only outside ASCII words.
      if ch == "’", let previous, previous.isASCII, previous.isLetter || previous.isNumber {
        mapped.append(ch)
      } else {
        mapped.append(
          halfwidthPunctuation[ch] ?? emojiCapableMarks[ch] ?? verticalPresentationForms[ch] ?? ch)
      }
      previous = ch
    }
    text = mapped
    for (pair, oneCell) in oneCellPairs {
      text = text.replacingOccurrences(of: pair, with: oneCell)
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    // Core Text's default line advance in vertical frames is ~3em, leaving a
    // wide empty gap between columns; pin it to a fixed em multiple instead.
    let lineHeight = CTFontGetSize(font) * 1.5
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    return NSAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        NSAttributedString.Key(kCTVerticalFormsAttributeName as String): true,
      ]
    )
  }

  private static func fittedSize(
    of attributed: NSAttributedString, in size: CGSize
  ) -> (fitted: CGSize, visibleLength: Int) {
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    var fitRange = CFRange()
    let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
      framesetter, CFRange(location: 0, length: 0), frameAttributes, size, &fitRange
    )
    return (fitted, fitRange.length)
  }

  static func fits(text: String, font: CTFont, in size: CGSize) -> Bool {
    guard size.width > 0, size.height > 0 else { return false }
    let attributed = attributedText(text, font: font, color: CGColor(gray: 0, alpha: 1))
    let (_, visibleLength) = fittedSize(of: attributed, in: size)
    return visibleLength == attributed.length
  }

  // Largest capped size whose typeset still fits the bubble; the draw pass
  // scales down further if even the floor overflows.
  static func fittedFontSize(text: String, in size: CGSize, makeFont: (CGFloat) -> CTFont) -> CGFloat {
    guard size.width > 0, size.height > 0 else { return 12 }
    var fontSize = min(17, max(12, size.width * 0.55))
    for _ in 0..<5 {
      if fits(text: text, font: makeFont(fontSize), in: size) { break }
      let nextSize = max(8, fontSize * 0.85)
      if nextSize == fontSize { break }
      fontSize = nextSize
    }
    return fontSize
  }

  // Draws with a y-down view coordinate system; the context flip happens here.
  static func draw(text: String, font: CTFont, color: CGColor, in context: CGContext, size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    let attributed = attributedText(text, font: font, color: color)
    let (fitted, visibleLength) = fittedSize(of: attributed, in: size)
    guard fitted.width > 0, fitted.height > 0 else { return }
    var frameSize = fitted
    if visibleLength < attributed.length {
      // Once the font floor is reached the typeset still overflows the
      // bubble; lay out at view height with unconstrained width, then
      // scale the vector outlines down — complete but smaller beats
      // silently clipped.
      let (needed, _) = fittedSize(
        of: attributed, in: CGSize(width: 10000, height: size.height))
      if needed.width > 0, needed.height > 0 {
        frameSize = needed
      }
    }
    // Suggest rounds the fitted size to whole points and can land fractionally
    // below the laid-out line boxes; a frame narrower than that drops a whole
    // column from the layout, so give the rect a point of slack.
    let contentRect = CGRect(
      x: (size.width - frameSize.width) / 2 - 0.5,
      y: (size.height - frameSize.height) / 2 - 0.5,
      width: frameSize.width + 1,
      height: frameSize.height + 1
    )
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let frame = CTFramesetterCreateFrame(
      framesetter, CFRange(location: 0, length: 0), CGPath(rect: contentRect, transform: nil),
      frameAttributes
    )
    context.saveGState()
    let scale = min(1, min(size.width / frameSize.width, size.height / frameSize.height))
    context.translateBy(x: size.width / 2, y: size.height / 2)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -size.width / 2, y: -size.height / 2)
    context.textMatrix = .identity
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    CTFrameDraw(frame, context)
    context.restoreGState()
  }
}
