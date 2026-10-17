import SwiftUI

#if os(iOS) || os(tvOS)
  import UIKit

  final class MangaOverlayView: UIView {
    private var result: MangaPageTranslation?
    private var visible = true
    private var background: ReaderBackground = .system
    private var direction: MangaTranslationTextDirection = .auto
    private var shape: MangaBubbleShape = .ellipse
    private var sourceImageID: ObjectIdentifier?
    private var regionColors: [CGColor] = []

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
      direction: MangaTranslationTextDirection, shape: MangaBubbleShape, image: PlatformImage?
    ) {
      self.visible = visible
      let backgroundChanged = self.background != background
      self.background = background
      let directionChanged = self.direction != direction
      self.direction = direction
      self.shape = shape
      let imageID = image.map { ObjectIdentifier($0) }
      let imageChanged = imageID != sourceImageID
      sourceImageID = imageID
      if result != self.result || backgroundChanged || directionChanged || imageChanged {
        self.result = result
        regionColors = sampleColors(for: result, image: image)
        subviews.forEach { $0.removeFromSuperview() }
        if let result {
          for (index, region) in result.regions.enumerated() {
            let container = UIView()
            container.isUserInteractionEnabled = false

            let bubbleBackground = MangaBubbleBackgroundView()
            bubbleBackground.fillColor = UIColor(cgColor: regionColors[index])
            container.addSubview(bubbleBackground)

            if direction.usesVerticalLayout(for: region, targetLanguage: result.targetLanguage) {
              let bubble = MangaVerticalTextLabel()
              bubble.text = region.translatedText ?? region.text
              bubble.textColor = MangaBubbleBackground.textColor(on: regionColors[index])
              container.addSubview(bubble)
            } else {
              let bubble = UILabel()
              bubble.text = region.translatedText ?? region.text
              bubble.font = .systemFont(ofSize: 14, weight: .medium)
              bubble.textColor = UIColor(
                cgColor: MangaBubbleBackground.textColor(on: regionColors[index]))
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
      sourceImageID = nil
      regionColors = []
      subviews.forEach { $0.removeFromSuperview() }
      isHidden = true
    }

    private func sampleColors(for result: MangaPageTranslation?, image: PlatformImage?) -> [CGColor] {
      guard let result else { return [] }
      let normalized = image.flatMap(MangaBubbleBackground.normalizedCGImage(from:))
      return result.regions.map { region in
        let sampled = normalized.flatMap {
          MangaBubbleBackground.backgroundColor(in: $0, normalizedBox: region.box)
        }
        if background.appliesImageMultiplyBlend {
          let tint = UIColor(background.color).cgColor
          return sampled.map { MangaBubbleBackground.multiply($0, by: tint) } ?? tint
        }
        return sampled ?? UIColor.white.cgColor
      }
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      guard let result else { return }
      for (index, container) in subviews.enumerated() {
        guard index < result.regions.count else { continue }
        let region = result.regions[index]
        container.frame = CGRect(
          x: region.box.minX * bounds.width - 2,
          y: region.box.minY * bounds.height - 2,
          width: region.box.width * bounds.width + 4,
          height: region.box.height * bounds.height + 4
        )

        let feather = MangaBubbleBackground.feather(forBoxSize: container.bounds.size)
        if let bubbleBackground = container.subviews.first(where: {
          $0 is MangaBubbleBackgroundView
        }) as? MangaBubbleBackgroundView {
          bubbleBackground.frame = MangaBubbleBackground.backgroundFrame(
            forBoxSize: container.bounds.size, boxKind: result.boxKind, shape: shape)
          bubbleBackground.feather = feather
          bubbleBackground.shape = shape
        }

        let textFrame = MangaBubbleBackground.textFrame(
          forBoxSize: container.bounds.size, boxKind: result.boxKind, shape: shape)
        guard
          let child = container.subviews.first(where: {
            $0 is UILabel || $0 is MangaVerticalTextLabel
          })
        else { continue }
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
    private var shape: MangaBubbleShape = .ellipse
    private var sourceImageID: ObjectIdentifier?
    private var regionColors: [CGColor] = []

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
      direction: MangaTranslationTextDirection, shape: MangaBubbleShape, image: PlatformImage?
    ) {
      self.visible = visible
      let backgroundChanged = self.background != background
      self.background = background
      let directionChanged = self.direction != direction
      self.direction = direction
      self.shape = shape
      let imageID = image.map { ObjectIdentifier($0) }
      let imageChanged = imageID != sourceImageID
      sourceImageID = imageID
      if result != self.result || backgroundChanged || directionChanged || imageChanged {
        self.result = result
        regionColors = sampleColors(for: result, image: image)
        subviews.forEach { $0.removeFromSuperview() }
        if let result {
          for (index, region) in result.regions.enumerated() {
            let container = NSView()
            container.wantsLayer = true

            let bubbleBackground = MangaBubbleBackgroundView()
            bubbleBackground.fillColor = NSColor(cgColor: regionColors[index]) ?? .white
            container.addSubview(bubbleBackground)

            if direction.usesVerticalLayout(for: region, targetLanguage: result.targetLanguage) {
              let bubble = MangaVerticalTextLabel()
              bubble.text = region.translatedText ?? region.text
              bubble.textColor = MangaBubbleBackground.textColor(on: regionColors[index])
              container.addSubview(bubble)
            } else {
              let bubble = NSTextField()
              bubble.stringValue = region.translatedText ?? region.text
              bubble.font = .systemFont(ofSize: 14, weight: .medium)
              bubble.textColor =
                NSColor(cgColor: MangaBubbleBackground.textColor(on: regionColors[index]))
                ?? .black
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
      sourceImageID = nil
      regionColors = []
      subviews.forEach { $0.removeFromSuperview() }
      isHidden = true
    }

    private func sampleColors(for result: MangaPageTranslation?, image: PlatformImage?) -> [CGColor] {
      guard let result else { return [] }
      let normalized = image.flatMap(MangaBubbleBackground.normalizedCGImage(from:))
      return result.regions.map { region in
        let sampled = normalized.flatMap {
          MangaBubbleBackground.backgroundColor(in: $0, normalizedBox: region.box)
        }
        if background.appliesImageMultiplyBlend {
          let tint = NSColor(background.color).cgColor
          return sampled.map { MangaBubbleBackground.multiply($0, by: tint) } ?? tint
        }
        return sampled ?? NSColor.white.cgColor
      }
    }

    override func layout() {
      super.layout()
      guard let result else { return }
      for (index, container) in subviews.enumerated() {
        guard index < result.regions.count else { continue }
        let region = result.regions[index]
        container.frame = CGRect(
          x: region.box.minX * bounds.width - 2,
          y: region.box.minY * bounds.height - 2,
          width: region.box.width * bounds.width + 4,
          height: region.box.height * bounds.height + 4
        )

        let feather = MangaBubbleBackground.feather(forBoxSize: container.bounds.size)
        if let bubbleBackground = container.subviews.first(where: {
          $0 is MangaBubbleBackgroundView
        }) as? MangaBubbleBackgroundView {
          bubbleBackground.frame = MangaBubbleBackground.backgroundFrame(
            forBoxSize: container.bounds.size, boxKind: result.boxKind, shape: shape)
          bubbleBackground.feather = feather
          bubbleBackground.shape = shape
        }

        let textFrame = MangaBubbleBackground.textFrame(
          forBoxSize: container.bounds.size, boxKind: result.boxKind, shape: shape)
        guard
          let child = container.subviews.first(where: {
            $0 is NSTextField || $0 is MangaVerticalTextLabel
          })
        else { continue }
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
