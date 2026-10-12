import CoreText
import Foundation

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

enum MangaVerticalTextCompositor {
  private static let frameAttributes: CFDictionary =
    [
      kCTFrameProgressionAttributeName: NSNumber(value: CTFrameProgression.rightToLeft.rawValue)
    ] as CFDictionary

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

  // Draws with a y-down view coordinate system; the context flip happens here.
  static func draw(text: String, font: CTFont, color: CGColor, in context: CGContext, size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    let attributed = attributedText(text, font: font, color: color)
    let (fitted, _) = fittedSize(of: attributed, in: size)
    let contentRect = CGRect(
      x: (size.width - fitted.width) / 2,
      y: (size.height - fitted.height) / 2,
      width: fitted.width,
      height: fitted.height
    )
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let frame = CTFramesetterCreateFrame(
      framesetter, CFRange(location: 0, length: 0), CGPath(rect: contentRect, transform: nil),
      frameAttributes
    )
    context.saveGState()
    context.textMatrix = .identity
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    CTFrameDraw(frame, context)
    context.restoreGState()
  }
}
