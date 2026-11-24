#if os(iOS) || os(macOS)
  import Foundation

  enum WebPubPagedJavaScriptBuilder {
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
        var kmDarkFg = \(foregroundJSON);
        if (kmDarkFg) {
          window.__kmRewriteDarkText = function() {
            if (!document.body || !window.getComputedStyle) { return; }
            var all = document.body.querySelectorAll('*');
            for (var i = 0; i < all.length; i++) {
              var el = all[i];
              var cs = window.getComputedStyle(el);
              if (el.namespaceURI === 'http://www.w3.org/2000/svg') {
                if (el.tagName.toLowerCase() === 'text') {
                  el.style.setProperty('fill', kmDarkFg, 'important');
                  el.setAttribute('data-km-dark-pinned', 'fill');
                }
                continue;
              }
              var color = cs.color;
              var m = /rgba?\\(\\s*(\\d+)[,\\s]+(\\d+)[,\\s]+(\\d+)/.exec(color);
              if (!m) { continue; }
              var maxc = Math.max(+m[1], +m[2], +m[3]);
              var fill = cs.webkitTextFillColor || color;
              if (maxc <= 96) {
                el.style.setProperty('color', kmDarkFg, 'important');
                if (fill !== kmDarkFg) {
                  el.style.setProperty('-webkit-text-fill-color', kmDarkFg, 'important');
                }
                el.setAttribute('data-km-dark-pinned', 'color');
              } else if (fill !== color) {
                // An inherited fill wins over `color` at paint time; pin it
                // back so publisher-colored spans survive the dark override.
                el.style.setProperty('-webkit-text-fill-color', color, 'important');
                el.setAttribute('data-km-dark-pinned', 'fill');
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
              if (transparent / total <= 0.3) { return; }
              var parent = img.parentElement;
              var text = parent ? (parent.textContent || '').replace(/\\s+/g, '') : '';
              if (/[\\p{L}\\p{N}]/u.test(text)) {
                // Inline glyph surrogate inside a sentence: always invert.
                img.classList.add('km-inline-img');
                return;
              }
              if (opaque > 0 && dark / opaque > 0.25) {
                img.classList.add('km-mono-img');
              }
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
          document.addEventListener('load', function(event) {
            var t = event.target;
            if (t && t.tagName === 'IMG') { kmClassifyOneImage(t); }
          }, true);
          var kmRunDarkPass = function() {
            window.__kmRewriteDarkText();
            window.__kmClassifyImages(document.body);
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
        } else {
          // Theme switched back to light: drop the pins the dark pass wrote.
          window.__kmRewriteDarkText = null;
          window.__kmClassifyImages = null;
          if (document.body) {
            var pinned = document.body.querySelectorAll('[data-km-dark-pinned]');
            for (var i = 0; i < pinned.length; i++) {
              pinned[i].style.removeProperty('color');
              pinned[i].style.removeProperty('-webkit-text-fill-color');
              pinned[i].style.removeProperty('fill');
              pinned[i].removeAttribute('data-km-dark-pinned');
            }
            var classifiedImgs = document.body.querySelectorAll('img.km-mono-img, img.km-inline-img');
            for (var j = 0; j < classifiedImgs.length; j++) {
              classifiedImgs[j].classList.remove('km-mono-img');
              classifiedImgs[j].classList.remove('km-inline-img');
              delete classifiedImgs[j].__kmClassified;
            }
          }
        }
        """
    }

    // Shared by every pagination script (this builder and both scrolled views'
    // inline scripts) so the guard and its wait cap cannot drift apart.
    static let fullExtentGuardScript = """
      var needsFullExtent = preferLast || target > 0;
      var imageWaitMaxAttempts = 600;
      var imagesPending = function() {
        var imgs = document.images;
        if (!imgs) { return false; }
        var pending = false;
        for (var i = 0; i < imgs.length; i++) {
          var img = imgs[i];
          if (img.loading === 'lazy') { img.loading = 'eager'; }
          if (!img.complete) { pending = true; continue; }
          // Broken images never decode; skip them instead of waiting forever.
          if (img.naturalWidth === 0) { continue; }
          // `complete` only means the bytes arrived; force a decode so the
          // reveal does not paint white raster bands for a few frames.
          if (img.decode && !img.__kmDecoded) {
            if (!img.__kmDecodeRequested) {
              img.__kmDecodeRequested = true;
              (function(el) {
                var done = function() { el.__kmDecoded = true; };
                el.decode().then(done, done);
              })(img);
            }
            pending = true;
          }
        }
        return pending;
      };
      """

    static func makePaginationScript(
      targetPageIndex: Int,
      preferLastPage: Bool,
      waitForLoadEvents: Bool,
      paginationLayout: WebPubPaginationLayout,
      generation: Int = 0
    ) -> String {
      """
      (function() {
        var generation = \(generation);
        window.__kmreaderPaginationGeneration = generation;
        var isCurrent = function() { return window.__kmreaderPaginationGeneration === generation; };
        var target = \(targetPageIndex);
        var preferLast = \(preferLastPage ? "true" : "false");
        \(paginationRuntimeScript(paginationLayout: paginationLayout))
        var lastReportedPageCount = 0;
        var hasFinalized = false;

        // Offsets past the first page depend on the full content extent; finalizing
        // while images are still in flight measures a short document and lands
        // mid-chapter once they load.
        \(fullExtentGuardScript)

        // Manifest metadata misses books whose publisher CSS declares a
        // vertical writing mode; probe the computed style like foliate does
        // and let the native side re-lay out with the vertical variant.
        var detectContentVertical = function() {
          if (!window.getComputedStyle || !document.body) { return false; }
          var wm = window.getComputedStyle(document.body).writingMode || '';
          if (wm.indexOf('vertical') === 0) { return true; }
          var first = document.body.firstElementChild;
          if (first) {
            var fwm = window.getComputedStyle(first).writingMode || '';
            if (fwm.indexOf('vertical') === 0) { return true; }
          }
          return false;
        };

        var finalize = function() {
          if (!isCurrent()) return;
          if (hasFinalized) return;
          hasFinalized = true;

          if (window.__kmRewriteDarkText) { window.__kmRewriteDarkText(); }
          if (window.__kmClassifyImages) { window.__kmClassifyImages(document.body); }

          var metrics = measurePagination();
          var pageWidth = metrics.pageWidth;
          var currentWidth = metrics.currentWidth;
          // Tolerate scrollWidth integer rounding against the fractional pitch.
          var total = Math.max(1, Math.ceil(currentWidth / pageWidth - 0.002));
          var finalTarget = preferLast ? (total - 1) : Math.max(0, Math.min(total - 1, target));

          scrollToLogicalOffset(pageWidth * finalTarget, false);

          lastReportedPageCount = total;

          setTimeout(function() {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerBridge) {
              window.webkit.messageHandlers.readerBridge.postMessage({
                type: 'ready',
                totalPages: total,
                currentPage: finalTarget,
                generation: generation
              });
            }
          }, 16);
        };

        var fontsSettled = false;
        if (document.fonts && document.fonts.ready) {
          document.fonts.ready.then(function() { fontsSettled = true; });
        } else {
          fontsSettled = true;
        }

        var startLayoutCheck = function() {
          var lastW = measurePagination().currentWidth;
          var stableCount = 0;
          var attempt = 0;

          var check = function() {
            if (!isCurrent()) return;
            if (hasFinalized) return;

            attempt++;
            // Only ever escalate horizontal -> vertical; reverse layouts from
            // RTL languages are legitimate and must not be second-guessed.
            if (attempt === 1 && !reverseScrollLeft && detectContentVertical()) {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerBridge) {
                window.webkit.messageHandlers.readerBridge.postMessage({
                  type: 'writingModeMismatch',
                  vertical: true,
                  generation: generation
                });
              }
              return;
            }
            var metrics = measurePagination();
            var currentW = metrics.currentWidth;
            var pageWidth = metrics.pageWidth;

            if (currentW === lastW && currentW > 0) {
              stableCount++;
            } else {
              stableCount = 0;
              lastW = currentW;
            }

            var isProbablyReady = (stableCount >= 4) || (fontsSettled && stableCount >= 2);
            if (needsFullExtent && currentW <= pageWidth && attempt < 40) {
              isProbablyReady = false;
            }

            var waitingForImages = needsFullExtent && attempt < imageWaitMaxAttempts && imagesPending();
            if ((isProbablyReady || attempt >= 60) && !waitingForImages) {
              finalize();
            } else {
              window.requestAnimationFrame(check);
            }
          };
          window.requestAnimationFrame(check);
        };

        var globalTimeout = setTimeout(function() {
          if (!isCurrent()) return;
          finalize();
        }, 10000);

        var loadStarted = false;
        var startOnce = function() {
          if (loadStarted) return;
          loadStarted = true;
          clearTimeout(globalTimeout);
          startLayoutCheck();
        };

        if (!\(waitForLoadEvents ? "true" : "false")) {
          startOnce();
          return;
        }

        if (document.readyState === 'complete') {
          startOnce();
        } else {
          if (document.readyState === 'interactive' || document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
              startOnce();
            });
          }
          window.addEventListener('load', function() {
            startOnce();
          });
        }

        // Late-loading images and publisher DOM mutations keep changing the
        // content extent after the first measure, so the watchers stay alive
        // for the chapter's lifetime instead of disconnecting once the size
        // looks stable. Every re-measure keeps the current page index, except
        // when the reader sits on the last page: then the end is tracked.
        var repaginateTimer = null;
        var repaginate = function() {
          if (!isCurrent() || !hasFinalized) { return; }
          var metrics = measurePagination();
          var pageWidth = metrics.pageWidth;
          var w = metrics.currentWidth;
          if (pageWidth <= 0 || w <= 0) { return; }
          // Tolerate scrollWidth integer rounding against the fractional pitch.
          var total = Math.max(1, Math.ceil(w / pageWidth - 0.002));
          if (total === lastReportedPageCount) { return; }
          var keepIdx = Math.floor(currentLogicalOffset() / pageWidth);
          var wasAtEnd = keepIdx >= lastReportedPageCount - 1;
          lastReportedPageCount = total;
          var newPage = wasAtEnd ? (total - 1) : Math.max(0, Math.min(total - 1, keepIdx));
          scrollToLogicalOffset(pageWidth * newPage, false);
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerBridge) {
            window.webkit.messageHandlers.readerBridge.postMessage({
              type: 'pageCountUpdate',
              totalPages: total,
              currentPage: newPage,
              generation: generation
            });
          }
          if (window.__kmRewriteDarkText) { window.__kmRewriteDarkText(); }
          if (window.__kmClassifyImages) { window.__kmClassifyImages(document.body); }
        };
        var scheduleRepaginate = function() {
          if (repaginateTimer) { clearTimeout(repaginateTimer); }
          repaginateTimer = setTimeout(repaginate, 250);
        };

        if (window.ResizeObserver) {
          var ro = new ResizeObserver(function() {
            if (!isCurrent()) {
              ro.disconnect();
              return;
            }
            scheduleRepaginate();
          });
          ro.observe(document.documentElement);
          if (document.body) { ro.observe(document.body); }
        }

        if (window.MutationObserver) {
          var mo = new MutationObserver(function(mutations) {
            if (!isCurrent()) {
              mo.disconnect();
              return;
            }
            for (var i = 0; i < mutations.length; i++) {
              var t = mutations[i].target;
              if (document.body && t && (t === document.body || document.body.contains(t))) {
                scheduleRepaginate();
                return;
              }
            }
          });
          mo.observe(document.documentElement, { childList: true, subtree: true });
        }

        // A pinned body height means late images never trigger the observers
        // above; capture-phase load events still reach us.
        document.addEventListener('load', function(event) {
          var t = event.target;
          if (t && t.tagName === 'IMG') { scheduleRepaginate(); }
        }, true);
      })();
      """
    }

    // Scrolls to an in-chapter anchor (footnote, endnote, cross-reference)
    // and lands on the page containing it. Returns false when the anchor
    // does not exist so the caller can fall back to the chapter start.
    static func makeScrollToAnchorScript(
      anchor: String,
      paginationLayout: WebPubPaginationLayout
    ) -> String {
      let anchorJSON = WebPubJavaScriptSupport.escapedJSONString(anchor)
      return """
        (function() {
          \(paginationRuntimeScript(paginationLayout: paginationLayout))
          var id = \(anchorJSON);
          var el = document.getElementById(id);
          if (!el) {
            try { el = document.querySelector('[name="' + id.replace(/"/g, '') + '"]'); } catch (e) { el = null; }
          }
          if (!el) { return false; }
          var metrics = measurePagination();
          var pageWidth = metrics.pageWidth;
          if (pageWidth <= 0) { return false; }
          var rect = el.getBoundingClientRect();
          var logical;
          if (reverseScrollLeft) {
            // Transforms shift content right by the active offset; the layout
            // position is the screen position minus that offset.
            logical = rect.left - activeLogicalOffset;
          } else {
            logical = rect.left + (window.pageXOffset || (document.documentElement ? document.documentElement.scrollLeft : 0) || 0);
          }
          var page = Math.max(0, Math.floor(logical / pageWidth));
          scrollToLogicalOffset(pageWidth * page, false);
          return true;
        })();
        """
    }

    /// Anchor landing for the continuous-scroll engine: the document scrolls
    /// vertically, so the element is simply scrolled into view.
    static func makeScrollToDocumentAnchorScript(anchor: String) -> String {
      let anchorJSON = WebPubJavaScriptSupport.escapedJSONString(anchor)
      return """
        (function() {
          var id = \(anchorJSON);
          var el = document.getElementById(id);
          if (!el) {
            try { el = document.querySelector('[name="' + id.replace(/"/g, '') + '"]'); } catch (e) { el = null; }
          }
          if (!el) { return false; }
          el.scrollIntoView({ block: 'start', behavior: 'instant' });
          return true;
        })();
        """
    }

    static func makeScrollToPageScript(
      pageIndex: Int,
      animated: Bool,
      paginationLayout: WebPubPaginationLayout
    ) -> String {
      makeScrollToLogicalOffsetScript(
        logicalOffset: "pageWidth * \(pageIndex)",
        animated: animated,
        paginationLayout: paginationLayout
      )
    }

    // Function body for callAsyncJavaScript: resolves after two animation frames,
    // i.e. once the target page has actually painted.
    static func makeScrollToPageAndSettleScript(
      pageIndex: Int,
      paginationLayout: WebPubPaginationLayout
    ) -> String {
      """
      \(paginationRuntimeScript(paginationLayout: paginationLayout))
      var pageWidth = measurePagination().pageWidth;
      scrollToLogicalOffset(pageWidth * \(pageIndex), false);
      await new Promise(function(resolve) {
        requestAnimationFrame(function() { requestAnimationFrame(resolve); });
      });
      return true;
      """
    }

    static func makeScrollToLogicalOffsetScript(
      logicalOffset: Double,
      animated: Bool,
      paginationLayout: WebPubPaginationLayout
    ) -> String {
      makeScrollToLogicalOffsetScript(
        logicalOffset: String(
          format: "%.4f",
          locale: Locale(identifier: "en_US_POSIX"),
          logicalOffset
        ),
        animated: animated,
        paginationLayout: paginationLayout
      )
    }

    private static func makeScrollToLogicalOffsetScript(
      logicalOffset: String,
      animated: Bool,
      paginationLayout: WebPubPaginationLayout
    ) -> String {
      """
      (function() {
        \(paginationRuntimeScript(paginationLayout: paginationLayout))
        var pageWidth = measurePagination().pageWidth;
        scrollToLogicalOffset(\(logicalOffset), \(animated ? "true" : "false"));
        return true;
      })();
      """
    }

    private static func paginationRuntimeScript(paginationLayout: WebPubPaginationLayout) -> String {
      """
      var reverseScrollLeft = \(paginationLayout.usesReverseScrollLeft ? "true" : "false");
      var activeLogicalOffset = 0;
      var unwrapLegacyPaginationStrip = function() {
        var body = document.body;
        if (!body) { return; }
        var wrapper = document.getElementById('kmreader-pagination-strip');
        if (!wrapper) { return; }
        wrapper.style.transition = '';
        wrapper.style.transform = '';
        while (wrapper.firstChild) {
          body.insertBefore(wrapper.firstChild, wrapper);
        }
        wrapper.remove();
      };
      var paginatedBodyChildren = function() {
        var body = document.body;
        if (!body) { return []; }
        return Array.prototype.filter.call(body.children, function(element) {
          return element.id !== 'kmreader-pagination-strip';
        });
      };
      var restorePageElementTransforms = function() {
        paginatedBodyChildren().forEach(function(element) {
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
      var applyPageElementTransforms = function(offset, animated) {
        var body = document.body;
        if (!body) { return; }
        unwrapLegacyPaginationStrip();
        if (offset <= 0) {
          activeLogicalOffset = 0;
          restorePageElementTransforms();
          body.classList.remove('kmreader-transform-pagination');
          body.removeAttribute('data-kmreader-logical-offset');
          return;
        }
        activeLogicalOffset = offset;
        body.classList.add('kmreader-transform-pagination');
        body.setAttribute('data-kmreader-logical-offset', String(offset));
        paginatedBodyChildren().forEach(function(element) {
          if (!element.hasAttribute('data-kmreader-transform-saved')) {
            element.setAttribute('data-kmreader-transform-saved', 'true');
            element.setAttribute('data-kmreader-original-transform', element.style.transform || '');
            element.setAttribute('data-kmreader-original-transition', element.style.transition || '');
            var computedTransform = window.getComputedStyle ? window.getComputedStyle(element).transform : '';
            if (!computedTransform || computedTransform === 'none') {
              computedTransform = '';
            }
            element.setAttribute('data-kmreader-author-transform', computedTransform);
          }
          var authorTransform = element.getAttribute('data-kmreader-author-transform') || '';
          var paginationTransform = 'translate3d(' + offset + 'px, 0, 0)';
          element.style.transition = animated ? 'transform 250ms ease' : 'none';
          element.style.transform = authorTransform
            ? (paginationTransform + ' ' + authorTransform)
            : paginationTransform;
        });
      };
      var currentLogicalOffset = function() {
        if (reverseScrollLeft) {
          // Native page turns run standalone scripts that only persist the
          // offset on <body>; the closure variable is stale afterwards.
          var body = document.body;
          if (body && body.hasAttribute('data-kmreader-logical-offset')) {
            var stored = parseFloat(body.getAttribute('data-kmreader-logical-offset') || '0');
            if (!isNaN(stored)) { return stored; }
          }
          return activeLogicalOffset;
        }
        var root = document.documentElement;
        var left = window.pageXOffset || (root ? root.scrollLeft : 0) || 0;
        return Math.abs(left);
      };
      var measurePagination = function() {
        var root = document.documentElement;
        var body = document.body;
        var previousOffset = activeLogicalOffset;
        if (body && body.hasAttribute('data-kmreader-logical-offset')) {
          previousOffset = parseFloat(body.getAttribute('data-kmreader-logical-offset') || '0') || previousOffset;
        }
        if (reverseScrollLeft) {
          unwrapLegacyPaginationStrip();
          restorePageElementTransforms();
        }
        // CSS column pitch is `100vw`, which resolves to the fractional
        // viewport width; clientWidth/innerWidth are integers and would drift
        // by up to 1px per page on fractional-width layouts.
        var pageWidth = (root && root.getBoundingClientRect ? root.getBoundingClientRect().width : 0)
          || (root && root.clientWidth)
          || window.innerWidth;
        if (!pageWidth || pageWidth <= 0) { pageWidth = 1; }
        var currentWidth = Math.max(
          root ? (root.scrollWidth || 0) : 0,
          body ? (body.scrollWidth || 0) : 0,
          pageWidth
        );
        if (reverseScrollLeft && previousOffset > 0) {
          applyPageElementTransforms(previousOffset, false);
        }
        return {
          pageWidth: pageWidth,
          currentWidth: currentWidth,
          maxScroll: Math.max(0, currentWidth - pageWidth)
        };
      };
      var scrollToLogicalOffset = function(logicalOffset, animated) {
        var metrics = measurePagination();
        var offset = Math.max(0, Math.min(logicalOffset, metrics.maxScroll));
        var root = document.documentElement;
        var body = document.body;
        if (reverseScrollLeft && body) {
          applyPageElementTransforms(offset, animated);
          window.scrollTo(0, 0);
          if (root) {
            root.scrollLeft = 0;
            root.scrollTop = 0;
          }
          body.scrollLeft = 0;
          body.scrollTop = 0;
          return;
        }
        var left = reverseScrollLeft ? -offset : offset;
        if (animated) {
          window.scrollTo({ left: left, top: 0, behavior: 'smooth' });
        } else {
          window.scrollTo(left, 0);
        }
        if (root) {
          root.scrollLeft = left;
          root.scrollTop = 0;
        }
        if (body) {
          body.scrollLeft = left;
          body.scrollTop = 0;
        }
      };
      """
    }

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
