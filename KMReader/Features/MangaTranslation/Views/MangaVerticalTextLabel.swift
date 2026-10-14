import CoreText
import Foundation

#if os(iOS) || os(tvOS)
  import UIKit

  final class MangaVerticalTextLabel: UIView {
    var text: String = "" {
      didSet { setNeedsDisplay() }
    }

    var textColor: CGColor = UIColor.black.cgColor {
      didSet { setNeedsDisplay() }
    }

    private var fontSize: CGFloat = 14

    override init(frame: CGRect) {
      super.init(frame: frame)
      isOpaque = false
      isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      isOpaque = false
      isUserInteractionEnabled = false
    }

    func fitFont() {
      fontSize = MangaVerticalTextCompositor.fittedFontSize(text: text, in: bounds.size) {
        UIFont.systemFont(ofSize: $0, weight: .medium) as CTFont
      }
      setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
      guard !text.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }
      let font = UIFont.systemFont(ofSize: fontSize, weight: .medium) as CTFont
      MangaVerticalTextCompositor.draw(
        text: text, font: font, color: textColor, in: context, size: bounds.size
      )
    }
  }
#elseif os(macOS)
  import AppKit

  final class MangaVerticalTextLabel: NSView {
    override var isFlipped: Bool { true }

    var text: String = "" {
      didSet { needsDisplay = true }
    }

    var textColor: CGColor = NSColor.black.cgColor {
      didSet { needsDisplay = true }
    }

    private var fontSize: CGFloat = 14

    func fitFont() {
      fontSize = MangaVerticalTextCompositor.fittedFontSize(text: text, in: bounds.size) {
        NSFont.systemFont(ofSize: $0, weight: .medium) as CTFont
      }
      needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
      guard !text.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
      let font = NSFont.systemFont(ofSize: fontSize, weight: .medium) as CTFont
      MangaVerticalTextCompositor.draw(
        text: text, font: font, color: textColor, in: context, size: bounds.size
      )
    }
  }
#endif
