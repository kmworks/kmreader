#if os(iOS)
  import UIKit
  import YueduCoreText
  import YueduCoreTextTypography

  struct CoreTextEpubLayoutConfiguration {
    private static let publisherFontFamilies = [
      "Iowan Old Style", "Sitka", "Sitka Text", "Palatino", "Book Antiqua", "URW Palladio L", "P052", "serif",
    ]

    var configuration: BrowserLayoutConfig
    let userStylesheet: String

    init(
      preferences: EpubThemePreferences,
      theme: ReaderTheme,
      viewportSize: CGSize,
      publicationLanguage: String?,
      publicationReadingProgression: WebPubReadingProgression?
    ) {
      let pageMargin = max(0, preferences.pageMargins) * 20
      let isVertical =
        ReadiumCSSLoader.resolveVariantSubdirectory(
          language: publicationLanguage,
          readingProgression: publicationReadingProgression
        ) == "cjk-vertical"
        || publicationReadingProgression == .ttb
        || publicationReadingProgression == .btt

      configuration = BrowserLayoutConfig(
        renderWidth: max(1, viewportSize.width - pageMargin * 2),
        renderHeight: max(1, viewportSize.height - pageMargin * 2),
        rootFontSize: 17 * (preferences.advancedLayout ? max(0.05, preferences.fontSize) : 1),
        fontFamilies: preferences.fontFamily.fontName.map { [$0] } ?? Self.publisherFontFamilies,
        textColor: UIColor(hex: theme.textColorHex) ?? .black,
        backgroundColor: UIColor(hex: theme.backgroundColorHex) ?? .white,
        contentInsets: UIEdgeInsets(
          top: pageMargin,
          left: pageMargin,
          bottom: pageMargin,
          right: pageMargin
        ),
        lineHeight: preferences.advancedLayout ? max(0.1, preferences.lineHeight) : nil,
        defaultTextAlignment: Self.defaultTextAlignment(for: preferences),
        writingMode: isVertical ? .verticalRTL : .horizontal,
        cjkTypographyStyle: CJKTypographyStyle.declared(publicationLanguage)
      )
      userStylesheet = Self.makeUserStylesheet(preferences: preferences, theme: theme)
    }

    private static func defaultTextAlignment(for preferences: EpubThemePreferences) -> NSTextAlignment {
      guard preferences.advancedLayout else { return .natural }
      switch preferences.textAlignment {
      case .publisherDefault:
        return .natural
      case .start:
        return .left
      case .justify:
        return .justified
      }
    }

    private static func makeUserStylesheet(
      preferences: EpubThemePreferences,
      theme: ReaderTheme
    ) -> String {
      var declarations: [String] = []
      if let fontName = preferences.fontFamily.fontName {
        declarations.append("font-family: \(cssFontFamily(fontName)) !important;")
      }
      if let fontWeight = preferences.fontWeight {
        declarations.append("font-weight: \(Int(fontWeight.rounded())) !important;")
      }
      if preferences.advancedLayout {
        declarations.append("word-spacing: \(cssRem(max(0, preferences.wordSpacing))) !important;")
        declarations.append("text-indent: \(cssRem(max(0, preferences.paragraphIndent))) !important;")
        declarations.append("letter-spacing: \(cssRem(max(0, preferences.letterSpacing))) !important;")
        declarations.append("margin-top: \(cssRem(max(0, preferences.paragraphSpacing))) !important;")
        declarations.append("margin-bottom: \(cssRem(max(0, preferences.paragraphSpacing))) !important;")
        switch preferences.textAlignment {
        case .publisherDefault:
          break
        case .start:
          declarations.append("text-align: start !important;")
        case .justify:
          declarations.append("text-align: justify !important;")
          declarations.append("hyphens: auto !important;")
        }
      }

      // Readium removes the browser's default body margin before applying reader insets.
      var styles = ["body { margin: 0 !important; }"]
      if !declarations.isEmpty {
        styles.append("body, body * {\n\(declarations.joined(separator: "\n"))\n}")
      }
      if theme.isDark {
        styles.append(
          """
          body, body * {
          color: \(theme.textColorHex) !important;
          background-color: transparent !important;
          border-color: currentColor !important;
          }
          html, body {
          background-color: \(theme.backgroundColorHex) !important;
          }
          a:link, a:link * {
          color: #63CAFF !important;
          }
          a:visited, a:visited * {
          color: #0099E5 !important;
          }
          """
        )
      }
      return styles.joined(separator: "\n\n")
    }

    private static func cssFontFamily(_ name: String) -> String {
      if name.contains("\"") || name.contains(" ") {
        return "\"" + name.replacingOccurrences(of: "\"", with: "\\\"") + "\""
      }
      return name
    }

    private static func cssRem(_ value: Double) -> String {
      String(format: "%.2frem", locale: Locale(identifier: "en_US_POSIX"), value)
    }
  }
#endif
