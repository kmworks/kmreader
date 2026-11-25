//
//  EpubFootnoteExtractor.swift
//
//

import Foundation
import SwiftSoup

/// Detects note markup in an EPUB chapter and converts it into a self-contained
/// preview: a sanitised HTML fragment with images inlined as data URLs.
///
/// Detection runs against the link *target* rather than the link itself, so
/// ordinary cross-references and table-of-contents anchors keep jumping.
nonisolated enum EpubFootnoteExtractor {
  static let maxBodyCharacters = 16_000
  static let maxTextCharacters = 2_000
  static let maxImages = 8
  static let maxImageBytes = 1_500_000
  static let maxInlineBytes = 6_000_000

  /// Returns the note addressed by `fragment` in `documentFileURL`, or `nil` when
  /// the target is not note markup.
  static func footnote(
    documentFileURL: URL,
    documentResourceURL: URL,
    rootURL: URL,
    fragment: String
  ) -> EpubFootnote? {
    guard !fragment.isEmpty,
      let data = try? Data(contentsOf: documentFileURL),
      let markup = decode(data),
      let document = try? SwiftSoup.parse(markup, documentResourceURL.absoluteString),
      let target = element(withIdentifier: fragment, in: document),
      let container = noteContainer(startingAt: target)
    else { return nil }

    let sanitizer = Sanitizer(rootURL: rootURL)
    let body = sanitizer.render(container: container)
    let text = ((try? container.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let cappedText = String(text.prefix(maxTextCharacters))
    let html = body.isEmpty ? "<p>\(escape(cappedText))</p>" : body

    let footnote = EpubFootnote(
      href: documentResourceURL.absoluteString,
      fragment: fragment,
      html: html,
      text: cappedText,
      truncated: sanitizer.truncated || cappedText.count < text.count
    )
    return footnote.isRenderable ? footnote : nil
  }

  // MARK: - Target lookup

  private static func element(withIdentifier identifier: String, in document: Document) -> Element? {
    if let elements = try? document.select("[id]") {
      for element in elements {
        if (try? element.attr("id")) == identifier { return element }
      }
    }
    if let anchors = try? document.select("a[name]") {
      for anchor in anchors {
        if (try? anchor.attr("name")) == identifier { return anchor }
      }
    }
    return nil
  }

  private static func noteContainer(startingAt target: Element) -> Element? {
    if isNote(target) { return target }
    var current = target.parent()
    var depth = 0
    while let element = current, depth < 3 {
      if isNote(element) { return element }
      current = element.parent()
      depth += 1
    }
    return nil
  }

  // MARK: - Note detection

  private static let noteTags: Set<String> = [
    "aside", "div", "section", "p", "li", "dd", "blockquote", "span", "article", "figure",
  ]

  private static let noteTypeTokens: Set<String> = [
    "footnote", "endnote", "rearnote", "note", "footnote-body", "endnote-body", "fn",
  ]

  private static let noteRoleTokens: Set<String> = ["doc-footnote", "doc-endnote"]

  private static let noteClassTokens: Set<String> = [
    "footnote", "endnote", "note", "fnote", "note-text", "aside-note", "footnote-content",
    "endnote-content", "note-content", "duokan-footnote-content", "calibre-footnote",
    "calibre-footnote-content",
  ]

  private static let noteClassPrefixes = ["fnote", "fn", "footnote", "endnote"]

  private static func isNote(_ element: Element) -> Bool {
    guard noteTags.contains(element.tagName().lowercased()) else { return false }

    if !tokens((try? element.attr("epub:type")) ?? "").isDisjoint(with: noteTypeTokens) {
      return true
    }
    if !tokens((try? element.attr("role")) ?? "").isDisjoint(with: noteRoleTokens) {
      return true
    }
    if tokens((try? element.attr("class")) ?? "").contains(where: matchesNoteClass) {
      return true
    }

    // Untyped notes normally carry a link back to the reference that pointed at them,
    // while section cross-references do not.
    let text = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count < maxTextCharacters * 2 else { return false }
    return containsBackReference(element)
  }

  private static func matchesNoteClass(_ name: String) -> Bool {
    if noteClassTokens.contains(name) { return true }
    for prefix in noteClassPrefixes where name.hasPrefix(prefix) {
      let suffix = name.dropFirst(prefix.count)
      if !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }) { return true }
    }
    return false
  }

  private static func containsBackReference(_ element: Element) -> Bool {
    guard let anchors = try? element.select("a[href]") else { return false }
    for anchor in anchors {
      let href = ((try? anchor.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if href.hasPrefix("#"), href.count > 1 { return true }
    }
    return false
  }

  private static func tokens(_ value: String) -> Set<String> {
    Set(value.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init))
  }

  // MARK: - Sanitising

  private static func decode(_ data: Data) -> String? {
    let encodings: [String.Encoding] = [
      .utf8,
      .utf16,
      .utf16LittleEndian,
      .utf16BigEndian,
      .isoLatin1,
      .windowsCP1252,
    ]
    for encoding in encodings {
      if let value = String(data: data, encoding: encoding) {
        return value
      }
    }
    return nil
  }

  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }

  private static func escapeAttribute(_ text: String) -> String {
    escape(text).replacingOccurrences(of: "\"", with: "&quot;")
  }

  private static func imageMediaType(for pathExtension: String) -> String? {
    switch pathExtension {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "svg": return "image/svg+xml"
    default: return nil
    }
  }

  /// Sanitises a note subtree into the small HTML subset the popup renders.
  private final class Sanitizer {
    init(rootURL: URL) {
      self.rootURL = rootURL
    }

    let rootURL: URL
    private(set) var truncated = false
    private var buffer = ""
    private var imageCount = 0
    private var inlineBytes = 0

    func render(container: Element) -> String {
      renderChildren(of: container)
      return buffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Traversal

    private func renderChildren(of element: Element) {
      for node in childNodes(of: element) {
        render(node: node)
      }
    }

    private func childNodes(of element: Element) -> [Node] {
      let count = element.childNodeSize()
      guard count > 0 else { return [] }
      return (0..<count).map { element.childNode($0) }
    }

    private func render(node: Node) {
      guard !truncated else { return }
      if let textNode = node as? TextNode {
        appendText(textNode.getWholeText())
        return
      }
      guard let element = node as? Element else { return }
      render(element: element)
    }

    private func render(element: Element) {
      guard !truncated else { return }
      switch element.tagName().lowercased() {
      case "script", "style", "iframe", "svg", "audio", "video", "object", "embed", "noscript",
        "link", "meta", "template", "form", "input", "button", "select", "textarea", "canvas",
        "map", "track", "source", "param", "wbr":
        return
      case "br":
        append("<br>")
      case "hr":
        append("<hr>")
      case "img":
        renderImage(element)
      case "a":
        renderLink(element)
      case "table":
        renderTable(element)
      case "ruby":
        renderRuby(element)
      case "li":
        renderBlock(element, prefix: "• ")
      case "p", "div", "section", "article", "aside", "blockquote", "dd", "dt", "figcaption",
        "figure", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "td", "th", "pre", "address",
        "center", "header", "footer", "main", "nav":
        renderBlock(element)
      case "b", "strong":
        renderWrapped(element, tag: "b")
      case "i", "em", "cite", "dfn", "var", "q":
        renderWrapped(element, tag: "i")
      case "u", "ins":
        renderWrapped(element, tag: "u")
      case "sup":
        renderWrapped(element, tag: "sup")
      case "sub":
        renderWrapped(element, tag: "sub")
      default:
        renderChildren(of: element)
      }
    }

    // MARK: Blocks

    private func renderBlock(_ element: Element, prefix: String = "") {
      let start = buffer.count
      append("<p>")
      append(prefix)
      let innerStart = buffer.count
      renderChildren(of: element)
      guard buffer.count > innerStart else {
        buffer = String(buffer.prefix(start))
        return
      }
      append("</p>")
    }

    private func renderWrapped(_ element: Element, tag: String) {
      let start = buffer.count
      append("<\(tag)>")
      let innerStart = buffer.count
      renderChildren(of: element)
      guard buffer.count > innerStart else {
        buffer = String(buffer.prefix(start))
        return
      }
      append("</\(tag)>")
    }

    private func renderLink(_ element: Element) {
      let href = ((try? element.absUrl("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard URL(string: href)?.scheme == EpubResourceScheme.scheme else {
        renderChildren(of: element)
        return
      }
      let start = buffer.count
      append("<a href=\"\(EpubFootnoteExtractor.escapeAttribute(href))\">")
      let innerStart = buffer.count
      renderChildren(of: element)
      guard buffer.count > innerStart else {
        buffer = String(buffer.prefix(start))
        return
      }
      append("</a>")
    }

    private func renderTable(_ element: Element) {
      guard let rows = try? element.select("tr") else { return }
      for row in rows {
        var cells: [String] = []
        for cell in row.children() {
          let text = ((try? cell.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          if !text.isEmpty { cells.append(text) }
        }
        guard !cells.isEmpty else { continue }
        append("<p>")
        append(EpubFootnoteExtractor.escape(cells.joined(separator: " · ")))
        append("</p>")
      }
    }

    private func renderRuby(_ element: Element) {
      var base = ""
      var annotation = ""
      for child in childNodes(of: element) {
        if let textNode = child as? TextNode {
          base += textNode.getWholeText()
          continue
        }
        guard let childElement = child as? Element else { continue }
        switch childElement.tagName().lowercased() {
        case "rt":
          annotation += (try? childElement.text()) ?? ""
        case "rp":
          continue
        default:
          base += (try? childElement.text()) ?? ""
        }
      }
      let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedAnnotation = annotation.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedAnnotation.isEmpty else {
        appendText(trimmedBase)
        return
      }
      appendText("\(trimmedBase)（\(trimmedAnnotation)）")
    }

    private func renderImage(_ element: Element) {
      guard imageCount < EpubFootnoteExtractor.maxImages else {
        truncated = true
        return
      }
      let src = ((try? element.absUrl("src")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard let inlined = inlineImageDataURL(src) else { return }
      let alt = ((try? element.attr("alt")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let markup = "<img src=\"\(inlined)\" alt=\"\(EpubFootnoteExtractor.escapeAttribute(alt))\">"
      guard inlineBytes + markup.count <= EpubFootnoteExtractor.maxInlineBytes else {
        truncated = true
        return
      }
      inlineBytes += markup.count
      imageCount += 1
      append(markup)
    }

    // MARK: Images

    private func inlineImageDataURL(_ src: String) -> String? {
      guard let url = URL(string: src), url.scheme == EpubResourceScheme.scheme,
        let relativePath = EpubResourceScheme.relativePath(from: url),
        let safePath = EpubResourceSafeRelativePath(relativePath),
        let mediaType = EpubFootnoteExtractor.imageMediaType(
          for: (safePath as NSString).pathExtension.lowercased()
        )
      else { return nil }
      let fileURL = rootURL.appendingPathComponent(safePath)
      guard let data = try? Data(contentsOf: fileURL),
        data.count <= EpubFootnoteExtractor.maxImageBytes
      else { return nil }
      return "data:\(mediaType);base64,\(data.base64EncodedString())"
    }

    // MARK: Output

    private func appendText(_ raw: String) {
      guard !raw.isEmpty else { return }
      let hasLeadingSpace = raw.first?.isWhitespace == true
      let hasTrailingSpace = raw.last?.isWhitespace == true
      let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
      guard !collapsed.isEmpty else {
        if hasLeadingSpace || hasTrailingSpace { append(" ") }
        return
      }
      var text = EpubFootnoteExtractor.escape(collapsed)
      if hasLeadingSpace { text = " " + text }
      if hasTrailingSpace { text += " " }
      append(text)
    }

    private func append(_ value: String) {
      guard !value.isEmpty, !truncated else { return }
      if buffer.count + value.count > EpubFootnoteExtractor.maxBodyCharacters {
        truncated = true
        return
      }
      buffer += value
    }
  }
}
