#if os(iOS) || os(macOS)
  import Foundation
  import SwiftUI
  import WebKit

  struct EpubSettingsPreviewView: View {
    let preferences: EpubThemePreferences

    @Environment(\.colorScheme) private var colorScheme
    @State private var customFontPath: String?

    private var customFontName: String? {
      preferences.fontFamily.fontName
    }

    var body: some View {
      PlatformPreviewWebView(
        preferences: preferences,
        colorScheme: resolvedColorScheme,
        customFontPath: customFontPath
      )
      .task(id: customFontName ?? "") {
        await loadCustomFontPath()
      }
    }

    private func loadCustomFontPath() async {
      guard let customFontName else {
        if customFontPath != nil {
          customFontPath = nil
        }
        return
      }

      do {
        let database = try await DatabaseOperator.database()
        let relativePath = try await database.fetchCustomFontPath(name: customFontName)
        let resolvedPath = relativePath.flatMap(FontFileManager.resolvePath)
        if customFontPath != resolvedPath {
          customFontPath = resolvedPath
        }
      } catch {
        if customFontPath != nil {
          customFontPath = nil
        }
      }
    }

    private var resolvedColorScheme: ColorScheme {
      preferences.resolvedColorScheme(fallbackColorScheme: colorScheme)
    }
  }

  private struct PreviewPayload: Equatable {
    let css: String
    let text1: String
    let text2: String
    let text3: String
    let language: String
    let direction: String?
  }

  private func basePreviewHTML() -> String {
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style id="kmreader-preview-style"></style>
    </head>
    <body>
      <p id="kmreader-preview-1"></p>
      <p id="kmreader-preview-2"></p>
      <p id="kmreader-preview-3"></p>
    </body>
    </html>
    """
  }

  private func makePreviewPayload(
    preferences: EpubThemePreferences,
    colorScheme: ColorScheme,
    customFontPath: String?
  ) -> PreviewPayload {
    let theme = preferences.resolvedTheme(for: colorScheme)
    let backgroundColor = theme.backgroundColorHex
    let textColor = theme.textColorHex

    let useAdvancedLayout = preferences.advancedLayout
    let fontScale = useAdvancedLayout ? preferences.fontSize : EpubConstants.defaultFontScale
    let fontSize = fontScale * 100
    let fontFamily =
      preferences.fontFamily.fontName.map { "'\($0)'" } ?? "system-ui, -apple-system, sans-serif"

    let fontWeightValue = preferences.fontWeight.map { Int($0.rounded()) }
    let letterSpacingEm =
      useAdvancedLayout ? preferences.letterSpacing : EpubConstants.defaultLetterSpacing
    let wordSpacingEm =
      useAdvancedLayout ? preferences.wordSpacing : EpubConstants.defaultWordSpacing
    let lineHeightValue =
      useAdvancedLayout ? preferences.lineHeight : EpubConstants.defaultLineHeight
    let paragraphSpacingEm =
      useAdvancedLayout ? preferences.paragraphSpacing : EpubConstants.defaultParagraphSpacing
    let paragraphIndentEm =
      useAdvancedLayout ? preferences.paragraphIndent : EpubConstants.defaultParagraphIndent
    let textAlignment = useAdvancedLayout ? preferences.textAlignment.readiumTextAlign : nil
    let bodyHyphens = useAdvancedLayout ? preferences.textAlignment.readiumBodyHyphens : nil

    let internalPadding = Int(round(max(0, preferences.pageMargins) * 20.0))

    var fontFaceCSS = ""
    if let fontName = preferences.fontFamily.fontName, let path = customFontPath {
      let fontURL = URL(fileURLWithPath: path)
      let fontFormat = path.hasSuffix(".otf") ? "opentype" : "truetype"
      fontFaceCSS = """
        @font-face {
          font-family: '\(fontName)';
          src: url('\(fontURL.absoluteString)') format('\(fontFormat)');
        }

        """
    }

    let language = Locale.current.identifier
    let languageCode = Locale.current.language.languageCode?.identifier ?? language
    let direction: String? =
      Locale.Language(identifier: languageCode).characterDirection == .rightToLeft
      ? "rtl"
      : nil

    let previewText1 = String(
      localized:
        "The quick brown fox jumps over the lazy dog. This is a sample text to preview your reading preferences.")
    let previewText2 = String(
      localized:
        "You can adjust the font size, spacing, and other settings to find what works best for you. Each paragraph demonstrates how the text will appear with your current choices."
    )
    let previewText3 = String(
      localized:
        "Reading should be comfortable and enjoyable. Take your time to customize these settings until you find the perfect combination."
    )

    let css = """
      \(fontFaceCSS)body {
        padding: \(internalPadding)px;
        margin: 0;
        background-color: \(backgroundColor);
        color: \(textColor);
        font-family: \(fontFamily);
        font-size: \(fontSize)%;
        \(fontWeightValue.map { "font-weight: \($0);" } ?? "")
        letter-spacing: \(letterSpacingEm)em;
        word-spacing: \(wordSpacingEm)em;
        line-height: \(lineHeightValue);
        \(textAlignment.map { "text-align: \($0);" } ?? "")
        \(bodyHyphens.map { "-webkit-hyphens: \($0); hyphens: \($0);" } ?? "")
      }
      p {
        margin: 0;
        margin-bottom: \(max(0, paragraphSpacingEm))em;
        text-indent: \(max(0, paragraphIndentEm))em;
      }
      """

    return PreviewPayload(
      css: css,
      text1: previewText1,
      text2: previewText2,
      text3: previewText3,
      language: language,
      direction: direction
    )
  }

  private func encodePreviewPayload(_ payload: PreviewPayload) -> String? {
    let dict: [String: Any] = [
      "css": payload.css,
      "text1": payload.text1,
      "text2": payload.text2,
      "text3": payload.text3,
      "lang": payload.language,
      "dir": payload.direction ?? NSNull(),
    ]
    guard
      let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
      let json = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return json
  }

  #if os(iOS)
    private struct PlatformPreviewWebView: UIViewRepresentable {
      let preferences: EpubThemePreferences
      let colorScheme: ColorScheme
      let customFontPath: String?

      func makeCoordinator() -> Coordinator {
        Coordinator()
      }

      func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.loadBaseHTMLIfNeeded(in: webView)
        return webView
      }

      func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
          webView: webView,
          preferences: preferences,
          colorScheme: colorScheme,
          customFontPath: customFontPath
        )
      }
    }
  #elseif os(macOS)
    private struct PlatformPreviewWebView: NSViewRepresentable {
      let preferences: EpubThemePreferences
      let colorScheme: ColorScheme
      let customFontPath: String?

      func makeCoordinator() -> Coordinator {
        Coordinator()
      }

      func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.loadBaseHTMLIfNeeded(in: webView)
        return webView
      }

      func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
          webView: webView,
          preferences: preferences,
          colorScheme: colorScheme,
          customFontPath: customFontPath
        )
      }
    }
  #endif

  extension PlatformPreviewWebView {
    final class Coordinator: NSObject, WKNavigationDelegate {
      private var isLoaded = false
      private var previewURL: URL?
      private var lastAppliedPayload: PreviewPayload?
      private var pendingPayload: PreviewPayload?

      func loadBaseHTMLIfNeeded(in webView: WKWebView) {
        guard let previewURL = preparePreviewFile() else { return }
        if webView.url?.standardizedFileURL != previewURL.standardizedFileURL {
          isLoaded = false
          webView.loadFileURL(
            previewURL,
            allowingReadAccessTo: previewURL.deletingLastPathComponent()
          )
        }
      }

      func update(
        webView: WKWebView,
        preferences: EpubThemePreferences,
        colorScheme: ColorScheme,
        customFontPath: String?
      ) {
        pendingPayload = makePreviewPayload(
          preferences: preferences,
          colorScheme: colorScheme,
          customFontPath: customFontPath
        )
        loadBaseHTMLIfNeeded(in: webView)
        applyPendingPayloadIfPossible(in: webView)
      }

      func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        applyPendingPayloadIfPossible(in: webView)
      }

      private func applyPendingPayloadIfPossible(in webView: WKWebView) {
        guard isLoaded, let payload = pendingPayload else { return }
        if lastAppliedPayload == payload { return }
        guard let payloadJSON = encodePreviewPayload(payload) else { return }

        let js = """
          (function() {
            var payload = \(payloadJSON);
            var root = document.documentElement;
            var body = document.body;
            if (!root || !body) { return false; }

            if (payload.lang) {
              root.setAttribute('lang', payload.lang);
              body.setAttribute('lang', payload.lang);
            }

            if (payload.dir) {
              root.setAttribute('dir', payload.dir);
              body.setAttribute('dir', payload.dir);
            } else {
              root.removeAttribute('dir');
              body.removeAttribute('dir');
            }

            var style = document.getElementById('kmreader-preview-style');
            if (!style) {
              style = document.createElement('style');
              style.id = 'kmreader-preview-style';
              document.head.appendChild(style);
            }
            style.textContent = payload.css || '';

            var p1 = document.getElementById('kmreader-preview-1');
            var p2 = document.getElementById('kmreader-preview-2');
            var p3 = document.getElementById('kmreader-preview-3');
            if (p1) { p1.textContent = payload.text1 || ''; }
            if (p2) { p2.textContent = payload.text2 || ''; }
            if (p3) { p3.textContent = payload.text3 || ''; }
            return true;
          })();
          """

        webView.evaluateJavaScript(js) { [weak self] result, error in
          guard let self else { return }
          let didApply = (result as? Bool) == true && error == nil
          if didApply {
            self.lastAppliedPayload = payload
          }
        }
      }

      private func preparePreviewFile() -> URL? {
        let directory = FontFileManager.fontsDirectory() ?? FileManager.default.temporaryDirectory
        let previewURL = directory.appendingPathComponent("preview.html")
        if previewURL == self.previewURL, FileManager.default.fileExists(atPath: previewURL.path) {
          return previewURL
        }

        let html = basePreviewHTML()
        guard let data = html.data(using: .utf8) else { return nil }
        do {
          try data.write(to: previewURL, options: [.atomic])
          self.previewURL = previewURL
          return previewURL
        } catch {
          return nil
        }
      }
    }
  }
#endif
