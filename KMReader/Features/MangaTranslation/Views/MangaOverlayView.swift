import SwiftUI

#if os(iOS) || os(tvOS)
  import UIKit

  final class MangaOverlayView: UIView {
    private var result: MangaPageTranslation?
    private var visible = true
    private var background: ReaderBackground = .system
    private var direction: MangaTranslationTextDirection = .auto

    private var bubbleColor: UIColor {
      background.appliesImageMultiplyBlend ? UIColor(background.color) : .white
    }

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      clipsToBounds = true
      isHidden = true
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      isUserInteractionEnabled = false
      clipsToBounds = true
      isHidden = true
    }

    func update(
      result: MangaPageTranslation?, visible: Bool, background: ReaderBackground,
      direction: MangaTranslationTextDirection
    ) {
      self.visible = visible
      let backgroundChanged = self.background != background
      self.background = background
      let directionChanged = self.direction != direction
      self.direction = direction
      if result != self.result || backgroundChanged || directionChanged {
        self.result = result
        subviews.forEach { $0.removeFromSuperview() }
        if let result {
          for region in result.regions {
            let container = UIView()
            container.backgroundColor = bubbleColor
            container.isUserInteractionEnabled = false
            container.layer.shadowColor = bubbleColor.cgColor
            container.layer.shadowOpacity = 0.85
            container.layer.shadowRadius = 12
            container.layer.shadowOffset = .zero

            if direction.usesVerticalLayout(for: region, targetLanguage: result.targetLanguage) {
              let bubble = MangaVerticalTextLabel()
              bubble.text = region.translatedText ?? region.text
              container.addSubview(bubble)
            } else {
              let bubble = UILabel()
              bubble.text = region.translatedText ?? region.text
              bubble.font = .systemFont(ofSize: 14, weight: .medium)
              bubble.textColor = .black
              bubble.textAlignment = .center
              bubble.numberOfLines = 0
              bubble.lineBreakMode = .byWordWrapping
              bubble.adjustsFontSizeToFitWidth = true
              bubble.minimumScaleFactor = 0.5
              bubble.backgroundColor = .clear
              bubble.isUserInteractionEnabled = false
              container.addSubview(bubble)
            }

            addSubview(container)
          }
        }
      }
      isHidden = result == nil || !visible
      setNeedsLayout()
    }

    func clear() {
      result = nil
      subviews.forEach { $0.removeFromSuperview() }
      isHidden = true
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      guard let result else { return }
      for (index, container) in subviews.enumerated() {
        guard index < result.regions.count, let child = container.subviews.first else { continue }
        let region = result.regions[index]
        container.frame = CGRect(
          x: region.box.minX * bounds.width - 2,
          y: region.box.minY * bounds.height - 2,
          width: region.box.width * bounds.width + 4,
          height: region.box.height * bounds.height + 4
        )

        let cornerRadius = min(32, max(12, min(container.bounds.width, container.bounds.height) * 0.4))
        container.layer.cornerRadius = cornerRadius
        container.layer.shadowPath = UIBezierPath(roundedRect: container.bounds, cornerRadius: cornerRadius).cgPath

        let textFrame = container.bounds.insetBy(
          dx: min(5, max(2, container.bounds.width * 0.04)),
          dy: min(4, max(1, container.bounds.height * 0.03))
        )
        child.frame = CGRect(
          x: textFrame.minX,
          y: textFrame.minY,
          width: max(0, textFrame.width),
          height: max(0, textFrame.height)
        )
        if let bubble = child as? UILabel {
          fitFont(for: bubble)
        } else if let bubble = child as? MangaVerticalTextLabel {
          bubble.fitFont()
        }
      }
    }

    private func fitFont(for bubble: UILabel) {
      guard bubble.bounds.width > 0, bubble.bounds.height > 0 else { return }
      var fontSize = min(17, max(12, bubble.bounds.height * 0.35))
      for _ in 0..<4 {
        bubble.font = .systemFont(ofSize: fontSize, weight: .medium)
        let neededSize = bubble.sizeThatFits(
          CGSize(width: bubble.bounds.width, height: .greatestFiniteMagnitude)
        )
        if neededSize.height <= bubble.bounds.height + 0.5 { break }
        let scale = max(0.7, bubble.bounds.height / max(neededSize.height, 1))
        let nextSize = max(8, fontSize * scale)
        if nextSize == fontSize { break }
        fontSize = nextSize
      }
      bubble.font = .systemFont(ofSize: fontSize, weight: .medium)
    }
  }
#elseif os(macOS)
  import AppKit

  final class MangaOverlayView: NSView {
    override var isFlipped: Bool { true }

    private var result: MangaPageTranslation?
    private var visible = true
    private var background: ReaderBackground = .system
    private var direction: MangaTranslationTextDirection = .auto

    private var bubbleColor: NSColor {
      background.appliesImageMultiplyBlend ? NSColor(background.color) : .white
    }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.masksToBounds = true
      isHidden = true
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      wantsLayer = true
      layer?.masksToBounds = true
      isHidden = true
    }

    func update(
      result: MangaPageTranslation?, visible: Bool, background: ReaderBackground,
      direction: MangaTranslationTextDirection
    ) {
      self.visible = visible
      let backgroundChanged = self.background != background
      self.background = background
      let directionChanged = self.direction != direction
      self.direction = direction
      if result != self.result || backgroundChanged || directionChanged {
        self.result = result
        subviews.forEach { $0.removeFromSuperview() }
        if let result {
          for region in result.regions {
            let container = NSView()
            container.wantsLayer = true
            container.layer?.backgroundColor = bubbleColor.cgColor
            container.layer?.shadowColor = bubbleColor.cgColor
            container.layer?.shadowOpacity = 0.85
            container.layer?.shadowRadius = 12
            container.layer?.shadowOffset = .zero

            if direction.usesVerticalLayout(for: region, targetLanguage: result.targetLanguage) {
              let bubble = MangaVerticalTextLabel()
              bubble.text = region.translatedText ?? region.text
              container.addSubview(bubble)
            } else {
              let bubble = NSTextField()
              bubble.stringValue = region.translatedText ?? region.text
              bubble.font = .systemFont(ofSize: 14, weight: .medium)
              bubble.textColor = .black
              bubble.alignment = .center
              bubble.lineBreakMode = .byWordWrapping
              bubble.maximumNumberOfLines = 0
              bubble.isEditable = false
              bubble.isSelectable = false
              bubble.isBordered = false
              bubble.drawsBackground = false
              bubble.cell?.wraps = true
              bubble.cell?.isScrollable = false
              container.addSubview(bubble)
            }

            addSubview(container)
          }
        }
      }
      isHidden = result == nil || !visible
      needsLayout = true
    }

    func clear() {
      result = nil
      subviews.forEach { $0.removeFromSuperview() }
      isHidden = true
    }

    override func layout() {
      super.layout()
      guard let result else { return }
      for (index, container) in subviews.enumerated() {
        guard index < result.regions.count, let child = container.subviews.first else { continue }
        let region = result.regions[index]
        container.frame = CGRect(
          x: region.box.minX * bounds.width - 2,
          y: region.box.minY * bounds.height - 2,
          width: region.box.width * bounds.width + 4,
          height: region.box.height * bounds.height + 4
        )

        let cornerRadius = min(32, max(12, min(container.bounds.width, container.bounds.height) * 0.4))
        container.layer?.cornerRadius = cornerRadius
        container.layer?.shadowPath =
          NSBezierPath(
            roundedRect: container.bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
          ).cgPath

        let textFrame = container.bounds.insetBy(
          dx: min(5, max(2, container.bounds.width * 0.04)),
          dy: min(4, max(1, container.bounds.height * 0.03))
        )
        child.frame = CGRect(
          x: textFrame.minX,
          y: textFrame.minY,
          width: max(0, textFrame.width),
          height: max(0, textFrame.height)
        )
        if let bubble = child as? NSTextField {
          fitFont(for: bubble)
        } else if let bubble = child as? MangaVerticalTextLabel {
          bubble.fitFont()
        }
      }
    }

    private func fitFont(for bubble: NSTextField) {
      guard bubble.bounds.width > 0, bubble.bounds.height > 0 else { return }
      var fontSize = min(17, max(12, bubble.bounds.height * 0.35))
      for _ in 0..<4 {
        bubble.font = .systemFont(ofSize: fontSize, weight: .medium)
        let neededSize = bubble.sizeThatFits(
          CGSize(width: bubble.bounds.width, height: .greatestFiniteMagnitude)
        )
        if neededSize.height <= bubble.bounds.height + 0.5 { break }
        let scale = max(0.7, bubble.bounds.height / max(neededSize.height, 1))
        let nextSize = max(8, fontSize * scale)
        if nextSize == fontSize { break }
        fontSize = nextSize
      }
      bubble.font = .systemFont(ofSize: fontSize, weight: .medium)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }
  }
#endif
