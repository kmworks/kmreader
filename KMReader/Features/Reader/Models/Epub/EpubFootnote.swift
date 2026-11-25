//
//  EpubFootnote.swift
//
//

import Foundation

/// A note preview extracted from an EPUB chapter, ready to render in the reader's
/// footnote popup.
///
/// The body arrives as a small, sanitised HTML fragment with images already
/// inlined as data URLs, so the popup needs no access to the book's resources.
nonisolated struct EpubFootnote: Identifiable, Equatable, Sendable {
  /// Resource URL of the chapter that holds the note.
  let href: String
  /// Fragment that addresses the note inside `href`.
  let fragment: String
  /// Sanitised HTML body. Images are inlined; unsupported markup is dropped.
  let html: String
  /// Plain text of the note, used for the empty-preview check.
  let text: String
  /// Whether the body was shortened, leaving something out of the preview.
  let truncated: Bool

  var id: String {
    "\(href)#\(fragment)"
  }

  var isRenderable: Bool {
    !html.isEmpty || !text.isEmpty
  }

  init(href: String, fragment: String, html: String, text: String, truncated: Bool) {
    self.href = href
    self.fragment = fragment
    self.html = html
    self.text = text
    self.truncated = truncated
  }
}
