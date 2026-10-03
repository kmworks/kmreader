import CoreGraphics
import CoreText
import Foundation

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

nonisolated enum TranslatedPageRenderer {
  static func render(source: CGImage, bubbles: [TranslatedBubble]) -> CGImage? {
    let pageWidth = source.width
    let pageHeight = source.height
    guard pageWidth > 0, pageHeight > 0 else { return nil }

    guard
      let context = CGContext(
        data: nil,
        width: pageWidth,
        height: pageHeight,
        bitsPerComponent: 8,
        bytesPerRow: pageWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.interpolationQuality = .high

    let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
    context.draw(source, in: pageRect)

    for bubble in bubbles {
      context.saveGState()
      context.clip(to: pageRect, mask: featheredMask(bubble.maskImage) ?? bubble.maskImage)
      context.setFillColor(bubble.backgroundColor)
      context.fill(pageRect)
      context.restoreGState()
    }

    for bubble in bubbles {
      drawTranslatedText(
        bubble.translatedText, in: bubble.regionRect, pageHeight: CGFloat(pageHeight), context: context)
    }

    return context.makeImage()
  }

  private static func featheredMask(_ mask: CGImage) -> CGImage? {
    let width = mask.width
    let height = mask.height
    guard width > 2, height > 2 else { return nil }
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      ),
      let data = context.data
    else { return nil }
    context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

    let count = width * height
    let source = data.bindMemory(to: UInt8.self, capacity: count)
    var blurred = [UInt8](repeating: 0, count: count)
    for y in 0..<height {
      for x in 0..<width {
        var sum = 0
        var samples = 0
        for dy in -1...1 {
          let ny = y + dy
          guard ny >= 0, ny < height else { continue }
          for dx in -1...1 {
            let nx = x + dx
            guard nx >= 0, nx < width else { continue }
            sum += Int(source[ny * width + nx])
            samples += 1
          }
        }
        blurred[y * width + x] = UInt8(sum / samples)
      }
    }
    source.initialize(from: blurred, count: count)
    return context.makeImage()
  }

  private static func drawTranslatedText(_ text: String, in regionRect: CGRect, pageHeight: CGFloat, context: CGContext)
  {
    let inner = regionRect.insetBy(dx: regionRect.width * 0.08, dy: regionRect.height * 0.08)
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard inner.width > 0, inner.height > 0, !trimmed.isEmpty else { return }

    var low: CGFloat = 8
    var high: CGFloat = 200
    var bestSize: CGFloat = 0
    var bestLines: [String] = []
    while high - low > 1 {
      let mid = ((low + high) / 2).rounded(.down)
      let font = PlatformFont.systemFont(ofSize: mid)
      let lines = wrappedLines(trimmed, font: font, maxWidth: inner.width)
      if linesFit(lines, font: font, in: inner) {
        bestSize = mid
        bestLines = lines
        low = mid
      } else {
        high = mid
      }
    }
    // Nothing fits even at the minimum size; still draw at it so the page keeps
    // its translation rather than silently dropping the bubble.
    if bestSize == 0 {
      bestSize = 8
      bestLines = wrappedLines(trimmed, font: PlatformFont.systemFont(ofSize: bestSize), maxWidth: inner.width)
    }
    guard !bestLines.isEmpty else { return }

    let font = PlatformFont.systemFont(ofSize: bestSize)
    let ctFont = font as CTFont
    let ascent = CTFontGetAscent(ctFont)
    let lineHeight = max(ascent + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont), bestSize * 1.1)
    let totalHeight = lineHeight * CGFloat(bestLines.count)

    let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    context.textMatrix = .identity
    var lineTop = inner.minY + (inner.height - totalHeight) / 2
    for line in bestLines {
      let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: black]
      let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
      let lineWidth = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
      let x = inner.minX + (inner.width - lineWidth) / 2
      // regionRect is top-left origin while the context is Quartz bottom-left origin.
      context.textPosition = CGPoint(x: x, y: pageHeight - (lineTop + ascent))
      CTLineDraw(ctLine, context)
      lineTop += lineHeight
    }
  }

  private static func linesFit(_ lines: [String], font: PlatformFont, in rect: CGRect) -> Bool {
    guard !lines.isEmpty else { return false }
    let ctFont = font as CTFont
    let lineHeight = max(
      CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont),
      font.pointSize * 1.1
    )
    guard CGFloat(lines.count) * lineHeight <= rect.height else { return false }
    return lines.allSatisfy { textWidth($0, font: font) <= rect.width }
  }

  private static func wrappedLines(_ text: String, font: PlatformFont, maxWidth: CGFloat) -> [String] {
    text.components(separatedBy: .newlines).flatMap { wrapParagraph($0, font: font, maxWidth: maxWidth) }
  }

  // CJK text has no spaces, so wrapping must break at tokenizer word boundaries
  // rather than splitting mid-word or mid-character runs blindly.
  private static func wrapParagraph(_ paragraph: String, font: PlatformFont, maxWidth: CGFloat) -> [String] {
    let nsParagraph = paragraph as NSString
    guard nsParagraph.length > 0,
      let tokenizer = CFStringTokenizerCreate(
        nil,
        paragraph as CFString,
        CFRange(location: 0, length: nsParagraph.length),
        kCFStringTokenizerUnitWordBoundary,
        nil
      )
    else { return [] }

    var tokens: [String] = []
    var tokenType = CFStringTokenizerGoToTokenAtIndex(tokenizer, 0)
    while !tokenType.isEmpty {
      let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
      tokens.append(nsParagraph.substring(with: NSRange(location: range.location, length: range.length)))
      tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
    }

    var lines: [String] = []
    var current = ""
    for token in tokens {
      let candidate = current + token
      if !current.isEmpty, textWidth(candidate, font: font) > maxWidth {
        lines.append(current)
        current = token.trimmingCharacters(in: .whitespaces)
      } else {
        current = candidate
      }
    }
    if !current.isEmpty {
      lines.append(current)
    }
    return lines
  }

  private static func textWidth(_ text: String, font: PlatformFont) -> CGFloat {
    NSAttributedString(string: text, attributes: [.font: font]).size().width
  }
}
