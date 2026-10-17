#if os(iOS)
  import UIKit

  /// Per-page translate action pinned to the page image's bottom-right corner:
  /// a material circle with a self-rendered glyph, styled after the system
  /// Live Text button, inverting to black while the translation overlay shows.
  final class MangaTranslationButton: UIButton {
    /// Matches the system Live Text button's circle and its inset from the
    /// image's bottom-right corner.
    static let size: CGFloat = 35
    static let cornerInset: CGFloat = 12

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let glyphView = UIImageView()
    private var appliedIcon: String?
    private var isPulsing = false

    /// The translate glyph is much wider than the phase icons, so it takes a
    /// smaller point size to keep every icon at roughly half the circle, like
    /// the system Live Text button.
    private static func symbolConfiguration(for icon: String) -> UIImage.SymbolConfiguration {
      UIImage.SymbolConfiguration(pointSize: icon == AppIcon.mangaTranslation ? 15 : 17, weight: .regular)
    }

    override var intrinsicContentSize: CGSize {
      CGSize(width: Self.size, height: Self.size)
    }

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
      layer.shadowColor = UIColor.black.cgColor
      layer.shadowOpacity = 0.25
      layer.shadowRadius = 2
      layer.shadowOffset = CGSize(width: 0, height: 1)
      blurView.isUserInteractionEnabled = false
      blurView.layer.cornerRadius = Self.size / 2
      blurView.layer.masksToBounds = true
      addSubview(blurView)
      glyphView.isUserInteractionEnabled = false
      glyphView.contentMode = .center
      glyphView.tintColor = .black
      addSubview(glyphView)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      blurView.frame = bounds
      glyphView.frame = bounds
      layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    func update(state: MangaTranslationButtonState) {
      isEnabled = state.isEnabled
      accessibilityLabel = state.accessibilityLabel
      alpha = state.isEnabled ? 1 : 0.5
      switch state.tint {
      case .none:
        // A nil effect shows the effect view's backgroundColor instead.
        blurView.effect = UIBlurEffect(style: .systemThickMaterial)
        blurView.backgroundColor = .clear
        glyphView.tintColor = .black
      case .active:
        blurView.effect = nil
        blurView.backgroundColor = .black
        glyphView.tintColor = .white
      case .failure:
        blurView.effect = UIBlurEffect(style: .systemThickMaterial)
        blurView.backgroundColor = .clear
        glyphView.tintColor = .systemRed
      }
      if appliedIcon != state.icon,
        let image = UIImage(systemName: state.icon, withConfiguration: Self.symbolConfiguration(for: state.icon))
      {
        if appliedIcon == nil {
          glyphView.image = image
        } else {
          glyphView.setSymbolImage(image, contentTransition: .replace)
        }
        appliedIcon = state.icon
      }
      if isPulsing != state.isBusy {
        isPulsing = state.isBusy
        if state.isBusy {
          glyphView.addSymbolEffect(.pulse, options: .repeating, animated: true)
        } else {
          glyphView.removeSymbolEffect(ofType: .pulse, animated: false)
        }
      }
    }
  }
#elseif os(macOS)
  import AppKit

  final class MangaTranslationButton: NSButton {
    static let size: CGFloat = 35
    static let cornerInset: CGFloat = 12

    private let effectView: NSVisualEffectView = {
      let blurView = NSVisualEffectView()
      blurView.material = .popover
      blurView.blendingMode = .withinWindow
      blurView.state = .active
      blurView.wantsLayer = true
      blurView.layer?.cornerRadius = MangaTranslationButton.size / 2
      blurView.layer?.masksToBounds = true
      return blurView
    }()
    private let glyphView = NSImageView()
    private var appliedIcon: String?
    private var isPulsing = false

    init() {
      super.init(frame: .zero)
      isBordered = false
      title = ""
      wantsLayer = true
      layer?.cornerRadius = Self.size / 2
      layer?.shadowColor = NSColor.black.cgColor
      layer?.shadowOpacity = 0.25
      layer?.shadowRadius = 2
      layer?.shadowOffset = CGSize(width: 0, height: -1)
      effectView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(effectView)
      glyphView.imageScaling = .scaleProportionallyDown
      glyphView.contentTintColor = .black
      glyphView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(glyphView)
      NSLayoutConstraint.activate([
        effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
        effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        effectView.topAnchor.constraint(equalTo: topAnchor),
        effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
        glyphView.centerXAnchor.constraint(equalTo: centerXAnchor),
        glyphView.centerYAnchor.constraint(equalTo: centerYAnchor),
        glyphView.widthAnchor.constraint(equalTo: widthAnchor),
        glyphView.heightAnchor.constraint(equalTo: heightAnchor),
      ])
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
      super.layout()
      if let layer {
        layer.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
      }
    }

    func update(state: MangaTranslationButtonState) {
      isEnabled = state.isEnabled
      alphaValue = state.isEnabled ? 1 : 0.5
      switch state.tint {
      case .none:
        effectView.isHidden = false
        layer?.backgroundColor = nil
        glyphView.contentTintColor = .black
      case .active:
        effectView.isHidden = true
        layer?.backgroundColor = NSColor.black.cgColor
        glyphView.contentTintColor = .white
      case .failure:
        effectView.isHidden = false
        layer?.backgroundColor = nil
        glyphView.contentTintColor = .systemRed
      }
      if appliedIcon != state.icon {
        // The translate glyph is much wider than the phase icons, so it takes
        // a smaller point size to keep every icon at roughly half the circle.
        glyphView.symbolConfiguration = NSImage.SymbolConfiguration(
          pointSize: state.icon == AppIcon.mangaTranslation ? 15 : 17, weight: .regular)
        let image = NSImage(systemSymbolName: state.icon, accessibilityDescription: nil)
        if appliedIcon == nil {
          glyphView.image = image
        } else {
          glyphView.setSymbolImage(image ?? NSImage(), contentTransition: .replace)
        }
        appliedIcon = state.icon
      }
      if isPulsing != state.isBusy {
        isPulsing = state.isBusy
        if state.isBusy {
          glyphView.addSymbolEffect(.pulse, options: .repeating, animated: true)
        } else {
          glyphView.removeSymbolEffect(ofType: .pulse, animated: false)
        }
      }
      setAccessibilityLabel(state.accessibilityLabel)
    }
  }
#endif
