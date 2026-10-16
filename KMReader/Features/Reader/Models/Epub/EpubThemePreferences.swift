//
// EpubThemePreferences.swift
//
//

import Foundation
import SwiftUI

nonisolated struct EpubThemePreferences: RawRepresentable, Equatable, Sendable {
  typealias RawValue = String

  // Keep this list in sync with makeReadiumPayload.
  static let readiumPropertyKeys: [String] = [
    "--RS__textColor",
    "--RS__backgroundColor",
    "--USER__textColor",
    "--USER__backgroundColor",
    "--USER__linkColor",
    "--USER__visitedColor",
    "--RS__disableOverflow",
    "--USER__view",
    "--USER__iOSPatch",
    "--USER__iPadOSPatch",
    "--USER__blendImages",
    "--USER__fontOverride",
    "--USER__fontFamily",
    "--USER__fontWeight",
    "--USER__colCount",
    "--USER__lineLength",
    "--USER__textAlign",
    "--USER__bodyHyphens",
    "--USER__fontSize",
    "--USER__lineHeight",
    "--USER__paraSpacing",
    "--USER__paraIndent",
    "--USER__wordSpacing",
    "--USER__letterSpacing",
  ]

  var theme: ThemeChoice
  var colorScheme: AppColorScheme
  var fontFamily: FontFamilyChoice
  var fontWeight: Double?
  var advancedLayout: Bool
  var fontSize: Double
  var wordSpacing: Double
  var paragraphSpacing: Double
  var paragraphIndent: Double
  var letterSpacing: Double
  var lineHeight: Double
  var columnCount: EpubColumnCount
  var textAlignment: EpubTextAlignment
  var pageMargins: Double

  init(
    theme: ThemeChoice = .system,
    colorScheme: AppColorScheme = .system,
    fontFamily: FontFamilyChoice = .publisher,
    fontWeight: Double? = nil,
    advancedLayout: Bool = false,
    fontSize: Double = EpubConstants.defaultFontScale,
    wordSpacing: Double = EpubConstants.defaultWordSpacing,
    paragraphSpacing: Double = EpubConstants.defaultParagraphSpacing,
    paragraphIndent: Double = EpubConstants.defaultParagraphIndent,
    letterSpacing: Double = EpubConstants.defaultLetterSpacing,
    lineHeight: Double = EpubConstants.defaultLineHeight,
    columnCount: EpubColumnCount = .auto,
    textAlignment: EpubTextAlignment = .publisherDefault,
    pageMargins: Double = EpubConstants.defaultPageMargins,
  ) {
    self.theme = theme
    self.colorScheme = colorScheme
    self.fontFamily = fontFamily
    self.fontSize = fontSize
    self.wordSpacing = wordSpacing
    self.paragraphSpacing = paragraphSpacing
    self.paragraphIndent = paragraphIndent
    self.pageMargins = pageMargins
    self.columnCount = columnCount
    self.letterSpacing = letterSpacing
    self.lineHeight = lineHeight
    self.textAlignment = textAlignment
    self.fontWeight = fontWeight
    self.advancedLayout = advancedLayout
  }

  init?(rawValue: String) {
    guard !rawValue.isEmpty else {
      self.init()
      return
    }

    guard let data = rawValue.data(using: .utf8),
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      self.init()
      return
    }

    let theme = (dict["theme"] as? String).flatMap(ThemeChoice.init) ?? .system
    let colorScheme = (dict["colorScheme"] as? String).flatMap(AppColorScheme.init) ?? .system
    let fontString = dict["fontFamily"] as? String ?? FontFamilyChoice.publisher.rawValue
    let font = FontFamilyChoice(rawValue: fontString)
    let rawFontWeight = dict["fontWeight"] as? Double
    let fontWeight = rawFontWeight.flatMap(Self.normalizedStoredFontWeight)
    let advancedLayout = dict["advancedLayout"] as? Bool ?? false
    let fontSize = dict["fontSize"] as? Double ?? EpubConstants.defaultFontScale
    let wordSpacing = dict["wordSpacing"] as? Double ?? EpubConstants.defaultWordSpacing
    let paragraphSpacing = dict["paragraphSpacing"] as? Double ?? EpubConstants.defaultParagraphSpacing
    let paragraphIndent = dict["paragraphIndent"] as? Double ?? EpubConstants.defaultParagraphIndent
    let letterSpacing = dict["letterSpacing"] as? Double ?? EpubConstants.defaultLetterSpacing
    let lineHeight = dict["lineHeight"] as? Double ?? EpubConstants.defaultLineHeight
    let columnCountRaw = dict["columnCount"] as? String ?? EpubColumnCount.auto.rawValue
    let columnCount = EpubColumnCount(rawValue: columnCountRaw) ?? .auto
    let textAlignmentRaw =
      dict["textAlignment"] as? String ?? EpubTextAlignment.publisherDefault.rawValue
    let textAlignment = EpubTextAlignment(rawValue: textAlignmentRaw) ?? .publisherDefault
    let rawPageMargins = dict["pageMargins"] as? Double ?? EpubConstants.defaultPageMargins
    let pageMargins = Self.normalizedPageMargins(rawPageMargins)

    self.init(
      theme: theme,
      colorScheme: colorScheme,
      fontFamily: font,
      fontWeight: fontWeight,
      advancedLayout: advancedLayout,
      fontSize: fontSize,
      wordSpacing: wordSpacing,
      paragraphSpacing: paragraphSpacing,
      paragraphIndent: paragraphIndent,
      letterSpacing: letterSpacing,
      lineHeight: lineHeight,
      columnCount: columnCount,
      textAlignment: textAlignment,
      pageMargins: pageMargins,
    )
  }

  var rawValue: String {
    var dict: [String: Any] = [
      "theme": theme.rawValue,
      "colorScheme": colorScheme.rawValue,
      "fontFamily": fontFamily.rawValue,
      "advancedLayout": advancedLayout,
      "fontSize": fontSize,
      "wordSpacing": wordSpacing,
      "paragraphSpacing": paragraphSpacing,
      "paragraphIndent": paragraphIndent,
      "letterSpacing": letterSpacing,
      "lineHeight": lineHeight,
      "columnCount": columnCount.rawValue,
      "textAlignment": textAlignment.rawValue,
      "pageMargins": pageMargins,
    ]
    if let fontWeight {
      dict["fontWeight"] = fontWeight
    }
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    {
      return json
    }
    return "{}"
  }

  func resolvedTheme(for colorScheme: ColorScheme? = nil) -> ReaderTheme {
    theme.resolvedTheme(for: colorScheme)
  }

  func resolvedColorScheme(fallbackColorScheme: ColorScheme) -> ColorScheme {
    colorScheme.colorScheme ?? fallbackColorScheme
  }

  func resolvedTheme(fallbackColorScheme: ColorScheme) -> ReaderTheme {
    theme.resolvedTheme(
      for: resolvedColorScheme(fallbackColorScheme: fallbackColorScheme)
    )
  }

  func makeReadiumPayload(
    theme: ReaderTheme,
    fontPath: String? = nil,
    flowStyle: EpubFlowStyle = .paged,
    rootURL: URL? = nil,
    viewportSize: CGSize? = nil
  ) -> (css: String, properties: [String: String?]) {
    let fontName = fontFamily.fontName
    let darkLinkColors = darkThemeLinkColors

    var properties: [String: String?] = [
      "--RS__textColor": theme.textColorHex,
      "--RS__backgroundColor": theme.backgroundColorHex,
    ]
    properties["--USER__view"] = flowStyle == .scrolled ? "readium-scroll-on" : nil
    properties["--RS__disableOverflow"] = flowStyle == .scrolled ? "readium-noOverflow-on" : nil
    #if os(iOS)
      properties["--USER__iOSPatch"] = "readium-iOSPatch-on"
      properties["--USER__iPadOSPatch"] = nil
    #else
      properties["--USER__iOSPatch"] = nil
      properties["--USER__iPadOSPatch"] = nil
    #endif
    properties["font-weight"] = nil

    let fontFamilyValue = fontName.map(cssFontFamilyValue)
    properties["--USER__fontOverride"] = fontFamilyValue == nil ? nil : "readium-font-on"
    properties["--USER__fontFamily"] = fontFamilyValue
    if let fontWeight {
      let fontWeightValue = readiumFontWeightValue(for: fontWeight)
      properties["--USER__fontWeight"] = "\(fontWeightValue)"
    } else {
      properties["--USER__fontWeight"] = nil
    }
    properties["--USER__colCount"] = resolvedReadiumColumnCount(flowStyle: flowStyle, for: viewportSize)
    properties["--USER__lineLength"] = readiumLineLengthValue(for: pageMargins)
    properties["--USER__textAlign"] = nil
    properties["--USER__bodyHyphens"] = nil

    if theme.isDark {
      properties["--USER__textColor"] = theme.textColorHex
      properties["--USER__backgroundColor"] = theme.backgroundColorHex
      properties["--USER__linkColor"] = darkLinkColors.link
      properties["--USER__visitedColor"] = darkLinkColors.visited
    } else {
      properties["--USER__textColor"] = nil
      properties["--USER__backgroundColor"] = nil
      properties["--USER__linkColor"] = nil
      properties["--USER__visitedColor"] = nil
    }
    properties["--USER__blendImages"] =
      shouldUseLightImageBlend(for: theme)
      ? "readium-blend-on" : nil

    if advancedLayout {
      let fontSizePercent = fontSize * 100
      let letterSpacingRem = max(0, letterSpacing)
      let wordSpacingRem = max(0, wordSpacing)
      let paragraphSpacingRem = max(0, paragraphSpacing)
      let paragraphIndentRem = max(0, paragraphIndent)

      properties["--USER__textAlign"] = textAlignment.readiumTextAlign
      properties["--USER__bodyHyphens"] = textAlignment.readiumBodyHyphens
      properties["--USER__fontSize"] = cssPercentage(fontSizePercent)
      properties["--USER__lineHeight"] = cssNumber(lineHeight)
      properties["--USER__paraSpacing"] = cssRem(paragraphSpacingRem)
      properties["--USER__paraIndent"] = cssRem(paragraphIndentRem)
      properties["--USER__wordSpacing"] = cssRem(wordSpacingRem)
      properties["--USER__letterSpacing"] = cssRem(letterSpacingRem)
    } else {
      properties["--USER__fontSize"] = nil
      properties["--USER__lineHeight"] = nil
      properties["--USER__paraSpacing"] = nil
      properties["--USER__paraIndent"] = nil
      properties["--USER__wordSpacing"] = nil
      properties["--USER__letterSpacing"] = nil
      properties["--USER__textAlign"] = nil
      properties["--USER__bodyHyphens"] = nil
    }

    let fontFaceCSS = makeFontFaceCSS(
      fontName: fontName,
      fontPath: fontPath,
      rootURL: rootURL
    )

    let darkTextColorOverrideCSS = makeDarkTextColorOverrideCSS(theme: theme)
    let paginationCompatibilityCSS = makePaginationCompatibilityCSS()
    return (
      css: fontFaceCSS + darkTextColorOverrideCSS + paginationCompatibilityCSS,
      properties: properties
    )
  }

  private func resolvedReadiumColumnCount(flowStyle: EpubFlowStyle, for viewportSize: CGSize?) -> String? {
    switch columnCount {
    case .one, .two:
      return columnCount.readiumValue
    case .auto:
      guard flowStyle == .paged else { return nil }
      guard let viewportSize else { return nil }
      let width = viewportSize.width
      return width >= 900 ? EpubColumnCount.two.readiumValue : EpubColumnCount.one.readiumValue
    }
  }

  private func readiumFontWeightValue(for weight: Double) -> Int {
    let normalizedWeight = min(
      max(weight.rounded(), EpubConstants.minimumFontWeight),
      EpubConstants.maximumFontWeight
    )
    return Int(normalizedWeight)
  }

  private static func normalizedStoredFontWeight(_ weight: Double) -> Double? {
    guard weight >= EpubConstants.minimumFontWeight else {
      return nil
    }
    return min(max(weight, EpubConstants.minimumFontWeight), EpubConstants.maximumFontWeight)
  }

  private func cssFontFamilyValue(_ name: String) -> String {
    if name.contains("\"") || name.contains(" ") {
      return "\"" + name.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    return name
  }

  private func makeFontFaceCSS(fontName: String?, fontPath: String?, rootURL: URL?) -> String {
    guard let fontName, let path = fontPath, rootURL != nil else {
      return ""
    }

    let fileName = URL(fileURLWithPath: path).lastPathComponent
    guard let fontURL = EpubResourceScheme.fontURL(fileName: fileName) else { return "" }
    let fileURLString = fontURL.absoluteString
    let fontFormat = path.hasSuffix(".otf") ? "opentype" : "truetype"

    return """
      @font-face {
        font-family: '\(fontName)';
        src: url('\(fileURLString)') format('\(fontFormat)');
      }

      """
  }

  private func readiumLineLengthValue(for pageMargins: Double) -> String {
    let normalizedMargins = max(0, pageMargins)
    let horizontalPadding = normalizedMargins * 20.0
    let totalInset = max(0, horizontalPadding * 2.0)
    return "calc(100% - \(cssNumber(totalInset))px)"
  }

  private func cssNumber(_ value: Double) -> String {
    String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
  }

  private func cssPercentage(_ value: Double) -> String {
    "\(cssNumber(value))%"
  }

  private func cssRem(_ value: Double) -> String {
    "\(cssNumber(value))rem"
  }

  private func makeDarkTextColorOverrideCSS(theme: ReaderTheme) -> String {
    guard theme.isDark else {
      return ""
    }

    return """
      :root[style*="--USER__textColor"] body {
        color: var(--USER__textColor) !important;
        -webkit-text-fill-color: var(--USER__textColor) !important;
      }

      :root[style*="--USER__textColor"] body *:not(a) {
        color: inherit !important;
        background-color: transparent !important;
        border-color: currentColor !important;
        -webkit-text-fill-color: currentColor !important;
      }

      :root[style*="--USER__textColor"] body svg text {
        fill: currentColor !important;
        stroke: none !important;
      }

      :root[style*="--USER__linkColor"] body a:link,
      :root[style*="--USER__linkColor"] body a:link * {
        color: var(--USER__linkColor) !important;
        -webkit-text-fill-color: var(--USER__linkColor) !important;
      }

      :root[style*="--USER__visitedColor"] body a:visited,
      :root[style*="--USER__visitedColor"] body a:visited * {
        color: var(--USER__visitedColor) !important;
        -webkit-text-fill-color: var(--USER__visitedColor) !important;
      }

      :root[style*="--USER__backgroundColor"] body,
      :root[style*="--USER__backgroundColor"] body * {
        background-color: transparent !important;
      }

      """
  }

  private var darkThemeLinkColors: (link: String, visited: String) {
    ("#63CAFF", "#0099E5")
  }

  private func makePaginationCompatibilityCSS() -> String {
    return """
      body {
        display: flow-root;
        height: auto !important;
        min-height: 100vh !important;
        max-height: none !important;
      }

      """
  }
  private func shouldUseLightImageBlend(for theme: ReaderTheme) -> Bool {
    switch theme {
    case .white, .lightQuiet, .lightSepia:
      return true
    default:
      return false
    }
  }

  private static func normalizedPageMargins(_ value: Double) -> Double {
    let normalized = value > 4.0 ? value / 20.0 : value
    return max(0, normalized)
  }
}
