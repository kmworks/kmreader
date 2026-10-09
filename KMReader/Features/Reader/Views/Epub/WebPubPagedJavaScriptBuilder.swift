#if os(iOS) || os(macOS)
  import Foundation

  enum WebPubPagedJavaScriptBuilder {
    static func makeInjectCSSScript(
      contentCSS: String,
      readiumProperties: [String: String?],
      readiumPropertyKeys: [String],
      language: String?,
      readingProgression: WebPubReadingProgression?
    ) -> String {
      let readiumAssets = ReadiumCSSLoader.cssAssets(
        language: language,
        readingProgression: readingProgression
      )
      let readiumVariant = ReadiumCSSLoader.resolveVariantSubdirectory(
        language: language,
        readingProgression: readingProgression
      )
      let paginationLayout = WebPubPaginationLayout.resolve(
        language: language,
        readingProgression: readingProgression
      )
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

          var meta = document.querySelector('meta[name=viewport]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.head.appendChild(meta);
          }
          meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');

          var style = document.getElementById('kmreader-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'kmreader-style';
            document.head.appendChild(style);
          }
          var hasStyles = document.querySelector("link[rel~='stylesheet'], style:not(#kmreader-style)") !== null;
          var css = atob('\(readiumBefore)') + "\\n"
            + (hasStyles ? "" : atob('\(readiumDefault)') + "\\n")
            + atob('\(readiumAfter)') + "\\n"
            + atob('\(customCSS)') + "\\n"
            + atob('\(pagedCompatibilityCSS)');
          style.textContent = css;
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

          return true;
        })();
        """
    }

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

        var finalize = function() {
          if (!isCurrent()) return;
          if (hasFinalized) return;
          hasFinalized = true;

          var metrics = measurePagination();
          var pageWidth = metrics.pageWidth;
          var currentWidth = metrics.currentWidth;
          var total = Math.max(1, Math.ceil(currentWidth / pageWidth));
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
            if ((preferLast || target > 0) && currentW <= pageWidth && attempt < 40) {
              isProbablyReady = false;
            }

            if (isProbablyReady || attempt >= 60) {
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

        if (window.ResizeObserver) {
          var stableScrollWidth = 0;
          var stableCheckCount = 0;
          var isPageCountLocked = false;
          var resizeDebounceTimer = null;

          var ro = new ResizeObserver(function() {
            if (!isCurrent()) {
              ro.disconnect();
              return;
            }
            if (isPageCountLocked) {
              return;
            }

            if (resizeDebounceTimer) {
              clearTimeout(resizeDebounceTimer);
            }

            resizeDebounceTimer = setTimeout(function() {
              var metrics = measurePagination();
              var w = metrics.currentWidth;
              var pageWidth = metrics.pageWidth;

              if (pageWidth > 0 && w > 0) {
                if (w === stableScrollWidth) {
                  stableCheckCount++;
                  if (stableCheckCount >= 3) {
                    isPageCountLocked = true;
                    ro.disconnect();
                    return;
                  }
                } else {
                  stableCheckCount = 0;
                  stableScrollWidth = w;

                  var total = Math.max(1, Math.ceil(w / pageWidth));
                  if (Math.abs(total - lastReportedPageCount) > 1) {
                    lastReportedPageCount = total;
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerBridge) {
                      window.webkit.messageHandlers.readerBridge.postMessage({
                        type: 'pageCountUpdate',
                        totalPages: total,
                        generation: generation
                      });
                    }
                  }
                }
              }
            }, 1000);
          });

          setTimeout(function() {
            stableScrollWidth = measurePagination().currentWidth;
            ro.observe(document.documentElement);
          }, 1500);
        }
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
        var pageWidth = (root && root.clientWidth) || window.innerWidth;
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
