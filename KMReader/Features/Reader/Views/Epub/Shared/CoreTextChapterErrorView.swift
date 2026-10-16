#if os(iOS)
  import UIKit

  @MainActor
  final class CoreTextChapterErrorView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    init(message: String, theme: ReaderTheme) {
      super.init(frame: .zero)

      iconView.image = UIImage(systemName: AppIcon.loadError)
      iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44)
      iconView.contentMode = .scaleAspectFit

      titleLabel.text = String(localized: "Failed to load media")
      titleLabel.font = .preferredFont(forTextStyle: .headline)
      titleLabel.textAlignment = .center
      titleLabel.numberOfLines = 0

      messageLabel.text = message
      messageLabel.font = .preferredFont(forTextStyle: .subheadline)
      messageLabel.textAlignment = .center
      messageLabel.numberOfLines = 0

      let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, messageLabel])
      stack.axis = .vertical
      stack.alignment = .center
      stack.spacing = 12
      stack.setCustomSpacing(20, after: iconView)

      addSubview(stack)
      stack.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        stack.centerXAnchor.constraint(equalTo: centerXAnchor),
        stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
        stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
      ])

      applyTheme(theme)
    }

    func applyTheme(_ theme: ReaderTheme) {
      backgroundColor = theme.uiColorBackground
      titleLabel.textColor = theme.uiColorText
      let secondary = theme.uiColorText.withAlphaComponent(0.6)
      messageLabel.textColor = secondary
      iconView.tintColor = secondary
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }
#endif
