#if os(iOS)
  import UIKit
  import YueduCoreText
  import YueduCoreTextTypography

  struct CoreTextEpubLayoutConfiguration {
    private static let rootFontSize: CGFloat = 16
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

      let horizontalMargin = isVertical ? 0 : pageMargin
      let verticalMargin = isVertical ? pageMargin : 0
      configuration = BrowserLayoutConfig(
        renderWidth: max(1, viewportSize.width - horizontalMargin * 2),
        renderHeight: max(1, viewportSize.height - verticalMargin * 2),
        rootFontSize: Self.rootFontSize,
        fontFamilies: preferences.fontFamily.fontName.map { [$0] } ?? Self.publisherFontFamilies,
        textColor: UIColor(hex: theme.textColorHex) ?? .black,
        backgroundColor: UIColor(hex: theme.backgroundColorHex) ?? .white,
        contentInsets: UIEdgeInsets(
          top: verticalMargin,
          left: horizontalMargin,
          bottom: verticalMargin,
          right: horizontalMargin
        ),
        lineHeight: preferences.advancedLayout ? max(0.1, preferences.lineHeight) : nil,
        letterSpacing: preferences.advancedLayout ? max(0, preferences.letterSpacing) * Self.rootFontSize : 0,
        defaultTextAlignment: Self.defaultTextAlignment(for: preferences),
        textTransform: Self.makeWordSpacingTransform(preferences: preferences),
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
      var globalDeclarations: [String] = []
      var bodyDeclarations: [String] = []
      var paragraphDeclarations: [String] = []
      var alignmentDeclarations: [String] = []
      var hyphens: String?

      if let fontName = preferences.fontFamily.fontName {
        globalDeclarations.append("font-family: \(cssFontFamily(fontName)) !important;")
      }
      if let fontWeight = preferences.fontWeight {
        bodyDeclarations.append("font-weight: \(Int(fontWeight.rounded())) !important;")
      }
      if preferences.advancedLayout {
        bodyDeclarations.append("font-size: \(cssPercentage(max(0.05, preferences.fontSize) * 100)) !important;")
        paragraphDeclarations.append("margin-top: \(cssRem(max(0, preferences.paragraphSpacing))) !important;")
        paragraphDeclarations.append("margin-bottom: \(cssRem(max(0, preferences.paragraphSpacing))) !important;")
        paragraphDeclarations.append("text-indent: \(cssRem(max(0, preferences.paragraphIndent))) !important;")
        switch preferences.textAlignment {
        case .publisherDefault:
          break
        case .start:
          alignmentDeclarations.append("text-align: start !important;")
          hyphens = "none"
        case .justify:
          alignmentDeclarations.append("text-align: justify !important;")
          hyphens = "auto"
        }
      }

      // Readium removes the browser's default body margin before applying reader insets.
      var styles = ["body { margin: 0 !important; }"]
      if !globalDeclarations.isEmpty {
        styles.append("body, body * {\n\(globalDeclarations.joined(separator: "\n"))\n}")
      }
      if !bodyDeclarations.isEmpty {
        var rule = "body {\n\(bodyDeclarations.joined(separator: "\n"))\n}"
        if preferences.fontWeight != nil {
          rule += "\nb, strong {\nfont-weight: bolder;\n}"
        }
        styles.append(rule)
      }
      if !paragraphDeclarations.isEmpty {
        styles.append("p {\n\(paragraphDeclarations.joined(separator: "\n"))\n}\np * {\ntext-indent: 0 !important;\n}")
      }
      if !alignmentDeclarations.isEmpty {
        var rule = "body, p, li, dd {\n\(alignmentDeclarations.joined(separator: "\n"))\n}"
        if let hyphens {
          rule += "\nbody, p, li, div, dd {\nhyphens: \(hyphens);\n}"
        }
        styles.append(rule)
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
          a, a * {
          color: #63CAFF !important;
          }
          """
        )
      }
      return styles.joined(separator: "\n\n")
    }

    private static func makeWordSpacingTransform(
      preferences: EpubThemePreferences
    ) -> ((NSMutableAttributedString) -> Void)? {
      guard preferences.advancedLayout else { return nil }
      let spacing = max(0, preferences.wordSpacing) * Self.rootFontSize
      guard spacing > 0 else { return nil }
      return { attributed in
        let text = attributed.string as NSString
        for match in Self.whitespaceExpression.matches(
          in: text as String, range: NSRange(location: 0, length: text.length))
        {
          let current =
            (attributed.attribute(.kern, at: match.range.location, effectiveRange: nil) as? NSNumber)?
            .doubleValue ?? 0
          attributed.addAttribute(.kern, value: current + spacing, range: match.range)
        }
      }
    }

    private static let whitespaceExpression = try! NSRegularExpression(pattern: #"\s+"#)

    private static func cssPercentage(_ value: Double) -> String {
      "\(cssNumber(value))%"
    }

    private static func cssFontFamily(_ name: String) -> String {
      if name.contains("\"") || name.contains(" ") {
        return "\"" + name.replacingOccurrences(of: "\"", with: "\\\"") + "\""
      }
      return name
    }

    private static func cssRem(_ value: Double) -> String {
      "\(cssNumber(value))rem"
    }

    private static func cssNumber(_ value: Double) -> String {
      String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
  }
#endif
