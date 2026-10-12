import CoreText
import Foundation

#if os(iOS) || os(tvOS)
  import UIKit

  final class MangaVerticalTextLabel: UIView {
    var text: String = "" {
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
      guard bounds.width > 0, bounds.height > 0 else { return }
      var size = min(17, max(12, bounds.width * 0.55))
      for _ in 0..<5 {
        let font = UIFont.systemFont(ofSize: size, weight: .medium) as CTFont
        if MangaVerticalTextCompositor.fits(text: text, font: font, in: bounds.size) { break }
        size = max(8, size * 0.85)
      }
      fontSize = size
      setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
      guard !text.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }
      let font = UIFont.systemFont(ofSize: fontSize, weight: .medium) as CTFont
      MangaVerticalTextCompositor.draw(
        text: text, font: font, color: UIColor.black.cgColor, in: context, size: bounds.size
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

    private var fontSize: CGFloat = 14

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
    }

    func fitFont() {
      guard bounds.width > 0, bounds.height > 0 else { return }
      var size = min(17, max(12, bounds.width * 0.55))
      for _ in 0..<5 {
        let font = NSFont.systemFont(ofSize: size, weight: .medium) as CTFont
        if MangaVerticalTextCompositor.fits(text: text, font: font, in: bounds.size) { break }
        size = max(8, size * 0.85)
      }
      fontSize = size
      needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
      guard !text.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
      let font = NSFont.systemFont(ofSize: fontSize, weight: .medium) as CTFont
      MangaVerticalTextCompositor.draw(
        text: text, font: font, color: NSColor.black.cgColor, in: context, size: bounds.size
      )
    }
  }
#endif
