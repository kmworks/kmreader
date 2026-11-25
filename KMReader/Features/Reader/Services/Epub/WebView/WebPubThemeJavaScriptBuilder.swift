#if os(iOS) || os(macOS)
  import Foundation

  enum WebPubThemeJavaScriptBuilder {
    static func makeInjectCSSScript(
      contentCSS: String,
      readiumProperties: [String: String?],
      readiumPropertyKeys: [String],
      language: String?,
      readingProgression: WebPubReadingProgression?,
      forceVerticalLayout: Bool = false
    ) -> String {
      let readiumAssets = ReadiumCSSLoader.cssAssets(
        language: language,
        readingProgression: readingProgression,
        forceVertical: forceVerticalLayout
      )
      let readiumVariant = ReadiumCSSLoader.resolveVariantSubdirectory(
        language: language,
        readingProgression: readingProgression,
        forceVertical: forceVerticalLayout
      )
      let paginationLayout = WebPubPaginationLayout.resolve(
        language: language,
        readingProgression: readingProgression,
        forceVertical: forceVerticalLayout
      )
      let darkThemeForeground = readiumProperties["--USER__textColor"] ?? nil
      let shouldSetDir = readiumVariant == "rtl" || (readingProgression == .rtl && readiumVariant != "cjk-vertical")
      let requestedView = readiumProperties["--USER__view"] ?? nil
      let usesTransformPagination =
        paginationLayout.usesReverseScrollLeft
        && requestedView != "readium-scroll-on"
      let pagedCompatibilityCSS = Data(
        pagedCompatibilityCSS(
          for: readiumVariant,
          usesTransformPagination: usesTransformPagination
        ).utf8
      ).base64EncodedString()

      let readiumBefore = Data(readiumAssets.before.utf8).base64EncodedString()
      let readiumDefault = Data(readiumAssets.defaultCSS.utf8).base64EncodedString()
      let readiumAfter = Data(readiumAssets.after.utf8).base64EncodedString()
      let customCSS = Data(contentCSS.utf8).base64EncodedString()

      var properties: [String: Any] = [:]
      for (key, value) in readiumProperties {
        properties[key] = value ?? NSNull()
      }
      let propertiesJSON = WebPubJavaScriptSupport.encodeJSON(properties, fallback: "{}")
      let propertyKeysJSON = WebPubJavaScriptSupport.encodeJSON(
        readiumPropertyKeys,
        fallback: "[]"
      )
      let languageJSON = WebPubJavaScriptSupport.escapedJSONString(language)
      return """
        (function() {
          var root = document.documentElement;
          var lang = \(languageJSON);
          if (lang) {
            if (!root.hasAttribute('lang')) { root.setAttribute('lang', lang); }
            if (!root.hasAttribute('xml:lang')) { root.setAttribute('xml:lang', lang); }
            if (document.body) {
              if (!document.body.hasAttribute('lang')) { document.body.setAttribute('lang', lang); }
              if (!document.body.hasAttribute('xml:lang')) { document.body.setAttribute('xml:lang', lang); }
            }
          }
          if (\(shouldSetDir ? "true" : "false")) {
            root.setAttribute('dir', 'rtl');
            if (document.body) { document.body.setAttribute('dir', 'rtl'); }
          }

          var props = \(propertiesJSON);
          Object.keys(props).forEach(function(key) {
            var value = props[key];
            if (value === null || value === undefined) {
              root.style.removeProperty(key);
            } else {
              root.style.setProperty(key, value, 'important');
            }
          });
          var knownKeys = \(propertyKeysJSON);
          knownKeys.forEach(function(key) {
            if (!(key in props)) {
              root.style.removeProperty(key);
            }
          });

          // At document-start injection the parser may not have produced the
          // head element yet; create it so styles apply before first paint.
          var head = document.head;
          if (!head) {
            head = document.createElement('head');
            document.documentElement.appendChild(head);
          }

          var meta = document.querySelector('meta[name=viewport]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            head.appendChild(meta);
          }
          meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');

          var style = document.getElementById('kmreader-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'kmreader-style';
          }
          var hasStyles = document.querySelector("link[rel~='stylesheet'], style:not(#kmreader-style)") !== null;
          var css = atob('\(readiumBefore)') + "\\n"
            + (hasStyles ? "" : atob('\(readiumDefault)') + "\\n")
            + atob('\(readiumAfter)') + "\\n"
            + atob('\(customCSS)') + "\\n"
            + atob('\(pagedCompatibilityCSS)');
          style.textContent = css;
          // Re-appending moves the style to the end of head so it keeps
          // winning the cascade when it was inserted at document start.
          head.appendChild(style);
          var transformPagination = \(usesTransformPagination ? "true" : "false");
          var restorePageElementTransforms = function() {
            if (!document.body) { return; }
            Array.prototype.forEach.call(document.body.children, function(element) {
              if (!element.hasAttribute('data-kmreader-transform-saved')) { return; }
              var originalTransform = element.getAttribute('data-kmreader-original-transform') || '';
              var originalTransition = element.getAttribute('data-kmreader-original-transition') || '';
              if (originalTransform) {
                element.style.transform = originalTransform;
              } else {
                element.style.removeProperty('transform');
              }
              if (originalTransition) {
                element.style.transition = originalTransition;
              } else {
                element.style.removeProperty('transition');
              }
              element.removeAttribute('data-kmreader-transform-saved');
              element.removeAttribute('data-kmreader-original-transform');
              element.removeAttribute('data-kmreader-original-transition');
              element.removeAttribute('data-kmreader-author-transform');
            });
          };
          var unwrapLegacyPaginationStrip = function() {
            if (!document.body) { return; }
            var wrapper = document.getElementById('kmreader-pagination-strip');
            if (!wrapper) { return; }
            wrapper.style.transition = '';
            wrapper.style.transform = '';
            while (wrapper.firstChild) {
              document.body.insertBefore(wrapper.firstChild, wrapper);
            }
            wrapper.remove();
          };
          if (document.body) {
            unwrapLegacyPaginationStrip();
            if (transformPagination) {
              document.body.classList.add('kmreader-transform-pagination');
            } else {
              document.body.classList.remove('kmreader-transform-pagination');
              document.body.removeAttribute('data-kmreader-logical-offset');
              restorePageElementTransforms();
            }
          }
          if (document.body && !transformPagination) {
            document.body.style.transition = '';
            document.body.style.transform = '';
          }

          \(darkContentScript(darkThemeForeground: darkThemeForeground))

          return true;
        })();
        """
    }

    // Dark-theme helpers mirrored from the Android rewriteDarkText pass and
    // the readest image classifier. Injected with the theme CSS so they are
    // defined before first paint; the pagination passes invoke them again
    // once publisher styles and images have settled.
    private static func darkContentScript(darkThemeForeground: String?) -> String {
      let foregroundJSON = WebPubJavaScriptSupport.escapedJSONString(darkThemeForeground)
      return """
        if (window.__kmClearDarkContent) { window.__kmClearDarkContent(); }
        var kmDarkFg = \(foregroundJSON);
        if (kmDarkFg) {
          var pinnedStyles = [];
          var pin = function(el, property, value) {
            pinnedStyles.push({
              el: el, property: property,
              value: el.style.getPropertyValue(property),
              priority: el.style.getPropertyPriority(property)
            });
            el.style.setProperty(property, value, 'important');
          };
          var rewrittenElements = new WeakSet();
          window.__kmRewriteDarkText = function() {
            if (!document.body || !window.getComputedStyle) { return; }
            var all = [document.body].concat(Array.from(document.body.querySelectorAll('*')));
            for (var i = 0; i < all.length; i++) {
              var el = all[i];
              if (rewrittenElements.has(el)) { continue; }
              rewrittenElements.add(el);
              var cs = window.getComputedStyle(el);
              if (el.namespaceURI === 'http://www.w3.org/2000/svg') {
                if (el.tagName.toLowerCase() === 'text') {
                  pin(el, 'fill', kmDarkFg);
                }
                continue;
              }
              var color = cs.color;
              var m = /rgba?\\(\\s*(\\d+)[,\\s]+(\\d+)[,\\s]+(\\d+)/.exec(color);
              if (!m) { continue; }
              var maxc = Math.max(+m[1], +m[2], +m[3]);
              var fill = cs.webkitTextFillColor || color;
              if (maxc <= 96) {
                pin(el, 'color', kmDarkFg);
                if (fill !== kmDarkFg) {
                  pin(el, '-webkit-text-fill-color', kmDarkFg);
                }
              } else if (fill !== color) {
                // An inherited fill wins over `color` at paint time; pin it
                // back so publisher-colored spans survive the dark override.
                pin(el, '-webkit-text-fill-color', color);
              }
            }
          };

          var kmClassifyOneImage = function(img) {
            if (img.__kmClassified) { return; }
            if (!img.complete || img.naturalWidth === 0) { return; }
            img.__kmClassified = true;
            try {
              var w = img.naturalWidth;
              var h = img.naturalHeight;
              var scale = Math.min(1, 96 / Math.max(w, h));
              var cw = Math.max(1, Math.round(w * scale));
              var ch = Math.max(1, Math.round(h * scale));
              var canvas = document.createElement('canvas');
              canvas.width = cw;
              canvas.height = ch;
              var ctx = canvas.getContext('2d', { willReadFrequently: true });
              ctx.drawImage(img, 0, 0, cw, ch);
              var data = ctx.getImageData(0, 0, cw, ch).data;
              var total = cw * ch;
              var transparent = 0;
              var opaque = 0;
              var dark = 0;
              for (var p = 0; p < data.length; p += 4) {
                if (data[p + 3] < 40) { transparent++; continue; }
                opaque++;
                var luma = 0.299 * data[p] + 0.587 * data[p + 1] + 0.114 * data[p + 2];
                if (luma < 96) { dark++; }
              }
              // Opaque illustrations must never be inverted.
              if (transparent / total <= 0.3 || opaque === 0 || dark / opaque <= 0.25) { return; }
              img.classList.add('km-invert-img');
            } catch (e) {
              // Tainted canvas or decode failure: leave the image alone.
            }
          };
          window.__kmClassifyImages = function(scope) {
            if (!document.body) { return; }
            var root = scope || document.body;
            var imgs = root.tagName === 'IMG' ? [root] : root.querySelectorAll('img');
            for (var i = 0; i < imgs.length; i++) { kmClassifyOneImage(imgs[i]); }
          };
          var onImageLoad = function(event) {
            var t = event.target;
            if (t && t.tagName === 'IMG') { kmClassifyOneImage(t); }
          };
          document.addEventListener('load', onImageLoad, true);
          var kmRunDarkPass = function() {
            if (window.__kmRewriteDarkText) { window.__kmRewriteDarkText(); }
            if (window.__kmClassifyImages) { window.__kmClassifyImages(document.body); }
          };
          // Document-start injection runs before <body> exists, and the
          // scrolled engine never re-invokes these functions; both passes are
          // idempotent, so schedule the initial run around document readiness.
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', kmRunDarkPass, { once: true });
          } else if (document.body) {
            kmRunDarkPass();
          }
          window.addEventListener('load', kmRunDarkPass, { once: true });
          window.__kmClearDarkContent = function() {
            document.removeEventListener('load', onImageLoad, true);
            document.removeEventListener('DOMContentLoaded', kmRunDarkPass);
            window.removeEventListener('load', kmRunDarkPass);
            pinnedStyles.forEach(function(saved) {
              if (saved.value) {
                saved.el.style.setProperty(saved.property, saved.value, saved.priority);
              } else {
                saved.el.style.removeProperty(saved.property);
              }
            });
            if (document.body) {
              document.body.querySelectorAll('img').forEach(function(img) {
                img.classList.remove('km-invert-img');
                delete img.__kmClassified;
              });
            }
            window.__kmClearDarkContent = null;
          };
        } else {
          window.__kmRewriteDarkText = null;
          window.__kmClassifyImages = null;
        }
        """
    }

    // Shared by paged and continuous pagination so image waiting cannot drift.
    private static func pagedCompatibilityCSS(
      for readiumVariant: String?,
      usesTransformPagination: Bool
    ) -> String {
      guard usesTransformPagination, readiumVariant == "cjk-vertical" else { return "" }
      return """
        body {
          min-height: 0 !important;
          max-height: var(--RS__defaultLineLength) !important;
          transform-origin: top right !important;
        }

        body.kmreader-transform-pagination > :not(#kmreader-pagination-strip) {
          transform-origin: top right !important;
          will-change: transform;
        }

        """
    }
  }
#endif
