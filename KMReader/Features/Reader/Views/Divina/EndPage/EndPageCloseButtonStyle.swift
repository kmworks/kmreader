#if os(iOS) || os(tvOS)
  import UIKit

  enum EndPageCloseButtonStyle {
    static func apply(to button: UIButton, textColor: UIColor) {
      var configuration = borderedButtonConfiguration()
      configuration.image = UIImage(systemName: AppIcon.close)
      configuration.imagePlacement = .leading
      configuration.imagePadding = 8
      configuration.preferredSymbolConfigurationForImage = buttonSymbolConfiguration
      configuration.title = String(localized: "Close")
      configuration.cornerStyle = .capsule
      button.configuration = configuration
      button.tintColor = textColor
      button.layer.shadowOpacity = 0
      button.layer.shadowRadius = 0
      button.layer.shadowOffset = .zero
    }

    private static func borderedButtonConfiguration() -> UIButton.Configuration {
      #if os(iOS)
        if #available(iOS 26.0, *) {
          return .glass()
        }
      #endif
      var configuration = UIButton.Configuration.bordered()
      var background = UIBackgroundConfiguration.clear()

      #if os(iOS)
        if UIAccessibility.isReduceTransparencyEnabled {
          background.backgroundColor = .systemBackground.withAlphaComponent(0.96)
        } else {
          background.visualEffect = UIBlurEffect(style: .systemThickMaterial)
          background.backgroundColor = .systemBackground.withAlphaComponent(0.12)
        }
        background.strokeColor = UIColor.label.withAlphaComponent(0.12)
      #elseif os(tvOS)
        background.backgroundColor = UIColor.black.withAlphaComponent(
          UIAccessibility.isReduceTransparencyEnabled ? 0.92 : 0.82
        )
        background.strokeColor = UIColor.white.withAlphaComponent(0.24)
      #endif

      background.strokeWidth = 1
      configuration.background = background
      return configuration
    }

    private static var buttonSymbolConfiguration: UIImage.SymbolConfiguration {
      UIImage.SymbolConfiguration(
        textStyle: .subheadline,
        scale: .small
      )
    }
  }
#elseif os(macOS)
  import AppKit

  enum EndPageCloseButtonStyle {
    static func apply(to button: NSButton, textColor: NSColor) {
      button.title = String(localized: "Close")
      button.image = NSImage(systemSymbolName: AppIcon.close, accessibilityDescription: nil)
      button.imagePosition = .imageLeading
      button.contentTintColor = textColor
    }
  }
#endif
