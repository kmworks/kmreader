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

  private static func attributedText(_ text: String, font: CTFont, color: CGColor) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
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
    let contentRect = CGRect(
      x: (size.width - frameSize.width) / 2,
      y: (size.height - frameSize.height) / 2,
      width: frameSize.width,
      height: frameSize.height
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
