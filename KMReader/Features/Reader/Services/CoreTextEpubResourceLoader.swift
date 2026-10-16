#if os(iOS)
  import CoreText
  import Foundation
  import SwiftSoup
  import UIKit
  import YueduCoreText

  @MainActor
  final class CoreTextEpubResourceLoader {
    private let rootURL: URL
    private let chapterURL: URL
    private var fonts: [String: UIFont] = [:]

    init(rootURL: URL, chapterURL: URL, customFontPath: String?) {
      self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
      self.chapterURL = chapterURL.standardizedFileURL.resolvingSymlinksInPath()
      if let customFontPath {
        prepareFont(at: URL(fileURLWithPath: customFontPath))
      }
    }

    var imageLoader: (String) -> UIImage? {
      { [weak self] source in
        self?.loadImage(source: source)
      }
    }

    var fontResolver: (([String], Int, Bool, CGFloat) -> UIFont?)? {
      { [weak self] families, weight, italic, size in
        self?.resolveFont(families: families, weight: weight, italic: italic, size: size)
      }
    }

    func makeInput(userStylesheet: String) throws -> CSSFrontendInput {
      let html = try loadText(from: chapterURL)
      let document = try SwiftSoup.parse(html, chapterURL.absoluteString)
      var stylesheets: [String] = []
      var visited: Set<URL> = []
      for link in try document.select("link[rel~=stylesheet]") {
        let href = try link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty else { continue }
        stylesheets.append(contentsOf: try loadStylesheet(href: href, relativeTo: chapterURL, visited: &visited))
      }
      for style in try document.select("style") {
        prepareFonts(in: try style.html(), relativeTo: chapterURL)
      }
      if !userStylesheet.isEmpty {
        stylesheets.append(userStylesheet)
      }
      return .currentCompatibility(html: html, cssTexts: stylesheets)
    }

    private func loadStylesheet(href: String, relativeTo baseURL: URL, visited: inout Set<URL>) throws -> [String] {
      guard let fileURL = resourceURL(for: href, relativeTo: baseURL) else {
        throw AppErrorType.missingRequiredData(message: "Missing EPUB stylesheet: \(href)")
      }
      guard visited.insert(fileURL).inserted else { return [] }

      let css = try loadText(from: fileURL)
      var stylesheets: [String] = []
      for match in Self.importExpression.matches(in: css, range: NSRange(css.startIndex..., in: css)) {
        guard match.numberOfRanges > 1, let range = match.range(at: 1) as NSRange?,
          let importRange = Range(range, in: css)
        else {
          continue
        }
        let importedHref = String(css[importRange])
        stylesheets.append(
          contentsOf: try loadStylesheet(href: importedHref, relativeTo: fileURL, visited: &visited)
        )
      }
      stylesheets.append(css)
      prepareFonts(in: css, relativeTo: fileURL)
      return stylesheets
    }

    private func loadText(from fileURL: URL) throws -> String {
      let data: Data
      do {
        data = try Data(contentsOf: fileURL)
      } catch {
        throw AppErrorType.fileReadError(path: fileURL.path, reason: error.localizedDescription)
      }
      for encoding in Self.textEncodings {
        if let text = String(data: data, encoding: encoding) {
          return text
        }
      }
      throw AppErrorType.dataCorrupted(message: "Unable to decode EPUB resource: \(fileURL.lastPathComponent)")
    }

    private func loadImage(source: String) -> UIImage? {
      if source.hasPrefix("data:") {
        guard let separator = source.firstIndex(of: ",") else { return nil }
        let metadata = source[..<separator]
        let payload = String(source[source.index(after: separator)...])
        if metadata.contains(";base64") {
          guard let data = Data(base64Encoded: payload) else { return nil }
          return UIImage(data: data)
        }
        guard let decoded = payload.removingPercentEncoding, let data = decoded.data(using: .utf8) else { return nil }
        return UIImage(data: data)
      }

      guard let fileURL = resourceURL(for: source, relativeTo: chapterURL),
        let data = try? Data(contentsOf: fileURL)
      else {
        return nil
      }
      return UIImage(data: data)
    }

    private func resourceURL(for source: String, relativeTo baseURL: URL) -> URL? {
      if source.hasPrefix(EpubResourceScheme.scheme + "://"), let schemeURL = URL(string: source),
        let relativePath = EpubResourceScheme.relativePath(from: schemeURL)
      {
        return existingFile(at: rootURL.appendingPathComponent(relativePath, isDirectory: false))
      }

      guard let candidate = URL(string: source, relativeTo: baseURL)?.absoluteURL.deletingFragment,
        candidate.isFileURL
      else {
        return nil
      }
      let standardized = candidate.standardizedFileURL.resolvingSymlinksInPath()
      guard isInsideRoot(standardized) else { return nil }
      if let existing = existingFile(at: standardized) {
        return existing
      }

      let relativePath = standardized.path.dropFirst(rootURL.path.count)
      let sanitizedComponents = relativePath.split(separator: "/").map {
        FileNameHelper.sanitizedFileName(String($0), defaultBaseName: "resource")
      }
      guard !sanitizedComponents.isEmpty else { return nil }
      let sanitized = rootURL.appendingPathComponent(sanitizedComponents.joined(separator: "/"))
      return existingFile(at: sanitized)
    }

    private func existingFile(at fileURL: URL) -> URL? {
      let standardized = fileURL.standardizedFileURL.resolvingSymlinksInPath()
      guard isInsideRoot(standardized), FileManager.default.fileExists(atPath: standardized.path) else {
        return nil
      }
      return standardized
    }

    private func isInsideRoot(_ fileURL: URL) -> Bool {
      let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
      return fileURL.path.hasPrefix(rootPath)
    }

    private func prepareFonts(in css: String, relativeTo baseURL: URL) {
      for match in Self.cssURLExpression.matches(in: css, range: NSRange(css.startIndex..., in: css)) {
        guard match.numberOfRanges > 1, let range = match.range(at: 1) as NSRange?,
          let sourceRange = Range(range, in: css)
        else {
          continue
        }
        let source = String(css[sourceRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard let fileURL = resourceURL(for: source, relativeTo: baseURL) else { continue }
        prepareFont(at: fileURL)
      }
    }

    private func prepareFont(at fileURL: URL) {
      guard let provider = CGDataProvider(url: fileURL as CFURL),
        let cgFont = CGFont(provider)
      else {
        return
      }
      let ctFont = CTFontCreateWithGraphicsFont(cgFont, 12, nil, nil)
      // Direct CTFont instances keep embedded fonts scoped to this publication.
      let font = ctFont as UIFont
      let names = [
        CTFontCopyFullName(ctFont) as String?,
        CTFontCopyFamilyName(ctFont) as String?,
        CTFontCopyPostScriptName(ctFont) as String?,
      ]
      for name in names {
        guard let name, !name.isEmpty else { continue }
        fonts[Self.normalizedFamily(name)] = font
      }
    }

    private func resolveFont(
      families: [String],
      weight: Int,
      italic _: Bool,
      size: CGFloat
    ) -> UIFont? {
      let uiWeight = Self.uiFontWeight(weight)
      for family in families {
        let key = Self.normalizedFamily(family)
        if let font = fonts[key] {
          return font.withSize(size)
        }
        if let font = UIFont(name: family, size: size) {
          return font
        }
        if let font = Self.genericFont(for: key, size: size, weight: uiWeight) {
          return font
        }
      }
      return .systemFont(ofSize: size, weight: uiWeight)
    }

    private static func genericFont(for family: String, size: CGFloat, weight: UIFont.Weight) -> UIFont? {
      switch family {
      case "serif":
        return UIFont(name: "Times New Roman", size: size) ?? .systemFont(ofSize: size, weight: weight)
      case "sans-serif", "system-ui", "-apple-system", "blinkmacsystemfont":
        return .systemFont(ofSize: size, weight: weight)
      case "monospace", "ui-monospace":
        return UIFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
      default:
        return nil
      }
    }

    private static func uiFontWeight(_ weight: Int) -> UIFont.Weight {
      switch weight {
      case ..<150: return .ultraLight
      case 150..<250: return .thin
      case 250..<350: return .light
      case 350..<450: return .regular
      case 450..<550: return .medium
      case 550..<650: return .semibold
      case 650..<750: return .bold
      case 750..<850: return .heavy
      default: return .black
      }
    }

    private static func normalizedFamily(_ name: String) -> String {
      name
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        .lowercased()
    }

    private static let textEncodings: [String.Encoding] = [
      .utf8,
      .utf16,
      .utf16LittleEndian,
      .utf16BigEndian,
      .isoLatin1,
      .windowsCP1252,
    ]

    private static let importExpression = try! NSRegularExpression(
      pattern: #"@import\s+(?:url\(\s*)?["']?([^"'\)\s]+)"#,
      options: [.caseInsensitive]
    )

    private static let cssURLExpression = try! NSRegularExpression(
      pattern: #"url\(\s*([^)]+?)\s*\)"#,
      options: [.caseInsensitive]
    )
  }
#endif
