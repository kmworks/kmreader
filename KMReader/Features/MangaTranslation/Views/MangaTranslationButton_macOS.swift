#if os(macOS)
  import AppKit

  /// Per-page translate action pinned to the page image's bottom-right corner:
  /// a material circle with a self-rendered glyph, styled after the system
  /// Live Text button, inverting to black while the translation overlay shows.
  final class MangaTranslationButton: NSButton {
    private let effectView: NSVisualEffectView = {
      let blurView = NSVisualEffectView()
      blurView.material = .popover
      blurView.blendingMode = .withinWindow
      blurView.state = .active
      blurView.wantsLayer = true
      blurView.layer?.cornerRadius = MangaTranslationButtonMetrics.size / 2
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
      layer?.cornerRadius = MangaTranslationButtonMetrics.size / 2
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
      switch state.style {
      case .normal:
        effectView.isHidden = false
        layer?.backgroundColor = nil
        glyphView.contentTintColor = .black
      case .inverted:
        effectView.isHidden = true
        layer?.backgroundColor = NSColor.black.cgColor
        glyphView.contentTintColor = .white
      case .failure:
        effectView.isHidden = false
        layer?.backgroundColor = nil
        glyphView.contentTintColor = .systemRed
      }
      if appliedIcon != state.icon {
        glyphView.symbolConfiguration = NSImage.SymbolConfiguration(
          pointSize: MangaTranslationButtonMetrics.glyphPointSize(for: state.icon), weight: .regular)
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
