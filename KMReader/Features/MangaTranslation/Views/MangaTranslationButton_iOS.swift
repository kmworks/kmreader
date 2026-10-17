#if os(iOS)
  import UIKit

  /// Per-page translate action pinned to the page image's bottom-right corner:
  /// a material circle with a self-rendered glyph, styled after the system
  /// Live Text button, inverting to black while the translation overlay shows.
  final class MangaTranslationButton: UIButton {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let glyphView = UIImageView()
    private var appliedIcon: String?
    private var isPulsing = false

    override var intrinsicContentSize: CGSize {
      CGSize(width: MangaTranslationButtonMetrics.size, height: MangaTranslationButtonMetrics.size)
    }

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
      layer.shadowColor = UIColor.black.cgColor
      layer.shadowOpacity = 0.25
      layer.shadowRadius = 2
      layer.shadowOffset = CGSize(width: 0, height: 1)
      blurView.isUserInteractionEnabled = false
      blurView.layer.cornerRadius = MangaTranslationButtonMetrics.size / 2
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
      switch state.style {
      case .normal:
        // A nil effect shows the effect view's backgroundColor instead.
        blurView.effect = UIBlurEffect(style: .systemThickMaterial)
        blurView.backgroundColor = .clear
        glyphView.tintColor = .black
      case .inverted:
        blurView.effect = nil
        blurView.backgroundColor = .black
        glyphView.tintColor = .white
      case .failure:
        blurView.effect = UIBlurEffect(style: .systemThickMaterial)
        blurView.backgroundColor = .clear
        glyphView.tintColor = .systemRed
      }
      if appliedIcon != state.icon,
        let image = UIImage(
          systemName: state.icon,
          withConfiguration: UIImage.SymbolConfiguration(
            pointSize: MangaTranslationButtonMetrics.glyphPointSize(for: state.icon), weight: .regular)
        )
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
#endif
