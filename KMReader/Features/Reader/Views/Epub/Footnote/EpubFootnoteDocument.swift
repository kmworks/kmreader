//
//  EpubFootnoteDocument.swift
//
//

import Foundation

/// Builds the self-contained HTML document rendered inside the footnote popup.
///
/// The document carries no external references: the note body is already
/// sanitised, and its images are inlined as data URLs.
nonisolated enum EpubFootnoteDocument {
  static func html(footnote: EpubFootnote, theme: ReaderTheme, scriptMessageHandler: String) -> String {
    let textColor = theme.textColorHex
    let linkColor = theme.isDark ? "#4CA6FF" : "#0066CC"
    let ruleColor = theme.isDark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.12)"

    return """
      <!DOCTYPE html>
      <html><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
      html, body { margin: 0; padding: 0; background: transparent; }
      body {
        font-family: -apple-system, system-ui, sans-serif;
        font-size: 16px;
        line-height: 1.5;
        color: \(textColor);
        -webkit-text-size-adjust: 100%;
        overflow-wrap: anywhere;
        word-wrap: break-word;
      }
      p { margin: 0 0 0.6em 0; }
      p:last-child { margin-bottom: 0; }
      a { color: \(linkColor); text-decoration: none; }
      img { display: block; max-width: 100%; height: auto; margin: 0.4em 0; }
      sup, sub { font-size: 0.72em; line-height: 0; }
      hr { border: 0; border-top: 1px solid \(ruleColor); margin: 0.6em 0; }
      </style>
      </head>
      <body><div id="kmreader-footnote">\(footnote.html)</div>
      <script>
      (function () {
        var handlers = window.webkit && window.webkit.messageHandlers;
        var handler = handlers && handlers.\(scriptMessageHandler);
        if (!handler) { return; }
        function report() {
          try { handler.postMessage({ type: "height", height: document.body.scrollHeight }); } catch (error) {}
        }
        document.addEventListener("load", function (event) {
          if (event.target && event.target.tagName === "IMG") { report(); }
        }, true);
        window.addEventListener("load", report);
        report();
      })();
      </script>
      </body></html>
      """
  }
}
