#if os(iOS) || os(macOS)
  import Foundation

  enum WebPubPagedJavaScriptBuilder {
    static let fullExtentGuardScript = """
      var needsFullExtent = preferLast || target > 0 || requiresFullExtent;
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
      generation: Int = 0,
      requiresFullExtent: Bool = false,
      targetProgression: Double? = nil
    ) -> String {
      """
      (function() {
        var generation = \(generation);
        window.__kmreaderPaginationGeneration = generation;
        var isCurrent = function() { return window.__kmreaderPaginationGeneration === generation; };
        var target = \(targetPageIndex);
        var targetProgression = \(targetProgression.map { String(min(max($0, 0), 1)) } ?? "null");
        var requiresFullExtent = \(requiresFullExtent ? "true" : "false");
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
          var requestedPage = targetProgression === null ? target : Math.floor(total * targetProgression);
          var finalTarget = preferLast ? (total - 1) : Math.max(0, Math.min(total - 1, requestedPage));

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
        // looks stable. Every re-measure preserves the current page index;
        // following the end is reserved for explicit last-page navigation at
        // pagination-ready time, so ordinary growth cannot skip unread pages.
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
          lastReportedPageCount = total;
          var newPage = Math.max(0, Math.min(total - 1, keepIdx));
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

        // WebKit activates in-chapter links itself, but the same touch also
        // reaches the host's tap gesture, which would then run a tap-zone
        // action for a link tap. Report the touch so native code can consume
        // the gesture instead of turning the page.
        if (!window.__kmreaderLinkTouchInstalled) {
          window.__kmreaderLinkTouchInstalled = true;
          var lastLinkTouchAt = 0;
          document.addEventListener('touchstart', function(event) {
            var node = event.target;
            if (!node || !node.closest) { return; }
            var link = node.closest('a[href]');
            if (!link) { return; }
            var now = Date.now();
            if (now - lastLinkTouchAt < 80) { return; }
            lastLinkTouchAt = now;
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerBridge) {
              window.webkit.messageHandlers.readerBridge.postMessage({
                type: 'linkTouch',
                href: link.getAttribute('href') || '',
                generation: window.__kmreaderPaginationGeneration
              });
            }
          }, true);
        }
      })();
      """
    }

    static func makeScrollDocumentScript(targetOffset: Double, duration: Double, token: Int) -> String {
      """
      (function() {
        var token = \(token);
        var isCurrent = function() { return window.__kmreaderScrollGeneration === token; };
        if (!isCurrent()) { return false; }
        var top = \(targetOffset);
        var duration = \(duration);
        var root = document.documentElement;
        var body = document.body;
        var scrolling = document.scrollingElement || root || body;
        var getCurrentTop = function() {
          return Math.max(
            0,
            window.scrollY
            || (scrolling && scrolling.scrollTop)
            || (root && root.scrollTop)
            || (body && body.scrollTop)
            || 0
          );
        };
        var setTop = function(value) {
          window.scrollTo(0, value);
          if (scrolling) { scrolling.scrollTop = value; }
          if (root) { root.scrollTop = value; }
          if (body) { body.scrollTop = value; }
        };
        var finish = function() {
          if (window.__kmreaderPostMetrics) {
            window.requestAnimationFrame(function() {
              if (isCurrent()) { window.__kmreaderPostMetrics('scroll'); }
            });
          }
        };
        if (window.__kmreaderScrollAnimationFrame) {
          window.cancelAnimationFrame(window.__kmreaderScrollAnimationFrame);
          window.__kmreaderScrollAnimationFrame = null;
        }
        if (!(duration > 0)) {
          setTop(top);
          finish();
          return true;
        }
        var startTop = getCurrentTop();
        var distance = top - startTop;
        if (Math.abs(distance) < 0.5) {
          setTop(top);
          finish();
          return true;
        }
        var startTime = null;
        var easeOutCubic = function(progress) {
          return 1 - Math.pow(1 - progress, 3);
        };
        var step = function(timestamp) {
          if (!isCurrent()) { return; }
          if (startTime === null) {
            startTime = timestamp;
          }
          var progress = Math.min(1, (timestamp - startTime) / (duration * 1000));
          var eased = easeOutCubic(progress);
          setTop(startTop + (distance * eased));
          if (progress < 1) {
            window.__kmreaderScrollAnimationFrame = window.requestAnimationFrame(step);
            return;
          }
          window.__kmreaderScrollAnimationFrame = null;
          finish();
        };
        window.__kmreaderScrollAnimationFrame = window.requestAnimationFrame(step);
        return true;
      })();
      """
    }

    static func makeScrolledPaginationScript(
      targetPageIndex: Int,
      preferLastPage: Bool,
      token: Int,
      requiresFullExtent: Bool,
      waitForStableLayout: Bool,
      targetProgression: Double? = nil
    ) -> String {
      let settlingScript: String
      if waitForStableLayout {
        settlingScript = """
          var startLayoutCheck = function() {
            var root = document.documentElement;
            var lastH = root.scrollHeight || document.body.scrollHeight;
            var stableCount = 0;
            var attempt = 0;

            var check = function() {
              if (!isCurrent() || hasFinalized) return;

              attempt++;
              var body = document.body;
              var scrolling = document.scrollingElement || root || body;
              var bodyRectHeight = body ? Math.ceil(body.getBoundingClientRect().height) : 0;
              var rootRectHeight = root ? Math.ceil(root.getBoundingClientRect().height) : 0;
              var currentH = Math.max(
                scrolling ? (scrolling.scrollHeight || 0) : 0,
                root ? (root.scrollHeight || 0) : 0,
                body ? (body.scrollHeight || 0) : 0,
                bodyRectHeight,
                rootRectHeight,
                0
              );
              var pageHeight =
                (window.visualViewport && window.visualViewport.height)
                || window.innerHeight
                || root.clientHeight;
              if (!pageHeight || pageHeight <= 0) { pageHeight = 1; }

              if (currentH === lastH && currentH > 0) {
                stableCount++;
              } else {
                stableCount = 0;
                lastH = currentH;
              }

              var isProbablyReady = (stableCount >= 4);
              if (needsFullExtent && currentH <= pageHeight && attempt < 40) {
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
            finalize();
          }, 10000);

          var loadStarted = false;
          var startOnce = function() {
            if (loadStarted) return;
            loadStarted = true;
            clearTimeout(globalTimeout);
            startLayoutCheck();
          };

          if (document.readyState === 'complete') {
            startOnce();
          } else {
            if (document.readyState === 'interactive' || document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', function() {
                setTimeout(startOnce, 500);
              });
            }
            window.addEventListener('load', function() {
              startOnce();
            });
          }
          """
      } else {
        settlingScript = """
          var timeout = setTimeout(finalize, 5000);
          var hasStarted = false;
          var start = function() {
            if (hasStarted) { return; }
            hasStarted = true;
            clearTimeout(timeout);
            var attempt = 0;
            var poll = function() {
              if (!isCurrent() || hasFinalized) return;
              attempt++;
              if (needsFullExtent && attempt < imageWaitMaxAttempts && imagesPending()) {
                window.requestAnimationFrame(poll);
                return;
              }
              finalize();
            };
            window.requestAnimationFrame(function() {
              window.requestAnimationFrame(poll);
            });
          };

          if (document.readyState === 'complete') {
            start();
          } else {
            window.addEventListener('load', start, { once: true });
            document.addEventListener('DOMContentLoaded', start, { once: true });
          }
          """
      }
      return """
        (function() {
          var target = \(targetPageIndex);
          var progression = \(targetProgression.map { String($0) } ?? "null");
          var requiresFullExtent = \(requiresFullExtent || targetProgression != nil ? "true" : "false");
          var preferLast = \(preferLastPage ? "true" : "false");
          var token = \(token);
          \(WebPubPagedJavaScriptBuilder.scrolledPaginationGenerationScript)
          var hasFinalized = false;
          \(WebPubPagedJavaScriptBuilder.scrolledPaginationRuntimeScript)

          // Offsets past the first page depend on the full content extent;
          // finalizing while images are still in flight measures a short
          // document and lands mid-chapter once they load.
          \(WebPubPagedJavaScriptBuilder.fullExtentGuardScript)
          var installMetricsBridge = function() {
            window.__kmreaderCurrentToken = token;
            if (window.__kmreaderPostMetrics) {
              return;
            }
            window.__kmreaderPostMetrics = function(type) {
              if (window.__kmreaderCurrentToken !== window.__kmreaderScrollGeneration) { return; }
              var root = document.documentElement;
              var body = document.body;
              var scrolling = document.scrollingElement || root || body;
              var viewportHeight =
                (window.visualViewport && window.visualViewport.height)
                || window.innerHeight
                || (root && root.clientHeight)
                || 1;
              if (!viewportHeight || viewportHeight <= 0) { viewportHeight = 1; }

              var bodyRectHeight = body ? Math.ceil(body.getBoundingClientRect().height) : 0;
              var rootRectHeight = root ? Math.ceil(root.getBoundingClientRect().height) : 0;
              var contentHeight = Math.max(
                scrolling ? (scrolling.scrollHeight || 0) : 0,
                root ? (root.scrollHeight || 0) : 0,
                body ? (body.scrollHeight || 0) : 0,
                bodyRectHeight,
                rootRectHeight,
                viewportHeight
              );
              var maxScroll = Math.max(0, contentHeight - viewportHeight);
              var scrollTop = Math.max(
                0,
                Math.min(
                  maxScroll,
                  window.scrollY
                  || (scrolling && scrolling.scrollTop)
                  || (root && root.scrollTop)
                  || (body && body.scrollTop)
                  || 0
                )
              );
              var total = Math.max(1, Math.ceil(contentHeight / viewportHeight));
              var currentPage = scrollPageIndex(scrollTop, total, maxScroll);

              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerBridge) {
                window.webkit.messageHandlers.readerBridge.postMessage({
                  type: type,
                  token: window.__kmreaderCurrentToken || 0,
                  totalPages: total,
                  currentPage: currentPage,
                  scrollTop: scrollTop,
                  contentHeight: contentHeight,
                  viewportHeight: viewportHeight
                });
              }
            };

            if (window.__kmreaderScrollMetricsInstalled) {
              return;
            }
            window.__kmreaderScrollMetricsInstalled = true;
            var scheduled = false;
            var scheduleMetrics = function(type) {
              if (scheduled) { return; }
              scheduled = true;
              window.requestAnimationFrame(function() {
                scheduled = false;
                window.__kmreaderPostMetrics(type || 'scroll');
              });
            };
            window.addEventListener('scroll', function() {
              scheduleMetrics('scroll');
            }, { passive: true });
            window.addEventListener('resize', function() {
              scheduleMetrics('scroll');
            });
            if (window.visualViewport) {
              window.visualViewport.addEventListener('resize', function() {
                scheduleMetrics('scroll');
              }, { passive: true });
            }
          };

          // WebKit activates in-chapter links itself, but the same touch also
          // reaches the host's tap gesture, which would then run a tap-zone
          // action for a link tap. Report the touch so native code can consume
          // the gesture instead of scrolling to another page.
          if (!window.__kmreaderScrolledLinkTouchInstalled) {
            window.__kmreaderScrolledLinkTouchInstalled = true;
            var lastLinkTouchAt = 0;
            document.addEventListener('touchstart', function(event) {
              var node = event.target;
              if (!node || !node.closest) { return; }
              var link = node.closest('a[href]');
              if (!link) { return; }
              var now = Date.now();
              if (now - lastLinkTouchAt < 80) { return; }
              lastLinkTouchAt = now;
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerBridge) {
                window.webkit.messageHandlers.readerBridge.postMessage({
                  type: 'linkTouch',
                  href: link.getAttribute('href') || '',
                  token: window.__kmreaderScrollGeneration
                });
              }
            }, true);
          }

          var finalize = function() {
            if (!isCurrent() || hasFinalized) return;
            hasFinalized = true;
            installMetricsBridge();

            var root = document.documentElement;
            var body = document.body;
            var scrolling = document.scrollingElement || root || body;
            var pageHeight =
              (window.visualViewport && window.visualViewport.height)
              || window.innerHeight
              || root.clientHeight;
            if (!pageHeight || pageHeight <= 0) { pageHeight = 1; }

            var bodyRectHeight = body ? Math.ceil(body.getBoundingClientRect().height) : 0;
            var rootRectHeight = root ? Math.ceil(root.getBoundingClientRect().height) : 0;
            var currentHeight = Math.max(
              scrolling ? (scrolling.scrollHeight || 0) : 0,
              root ? (root.scrollHeight || 0) : 0,
              body ? (body.scrollHeight || 0) : 0,
              bodyRectHeight,
              rootRectHeight,
              pageHeight
            );
            var total = Math.max(1, Math.ceil(currentHeight / pageHeight));
            var maxScroll = Math.max(0, currentHeight - pageHeight);

            var requested = preferLast ? total - 1 : (progression !== null ? Math.floor(total * progression) : target);
            var finalTarget = Math.max(0, Math.min(total - 1, requested));
            var offset = scrollPageOffset(finalTarget, total, maxScroll);

            window.scrollTo(0, offset);
            if (document.documentElement) { document.documentElement.scrollTop = offset; }
            if (document.body) { document.body.scrollTop = offset; }

            setTimeout(function() {
              if (isCurrent() && window.__kmreaderPostMetrics) {
                window.__kmreaderPostMetrics('ready');
              }
            }, 60);
          };
          \(settlingScript)
        })();
        """
    }

    static let scrolledPaginationGenerationScript = """
      window.__kmreaderScrollGeneration = token;
      if (window.__kmreaderScrollAnimationFrame) {
        window.cancelAnimationFrame(window.__kmreaderScrollAnimationFrame);
        window.__kmreaderScrollAnimationFrame = null;
      }
      var isCurrent = function() { return window.__kmreaderScrollGeneration === token; };
      """

    // Mirrors EpubScrollPagination so native and document offsets round-trip.
    static let scrolledPaginationRuntimeScript = """
      var scrollPageOffset = function(index, total, maxScroll) {
        if (total <= 1) { return 0; }
        return maxScroll * Math.max(0, Math.min(total - 1, index)) / (total - 1);
      };
      var scrollPageIndex = function(offset, total, maxScroll) {
        if (maxScroll <= 0) { return 0; }
        return Math.round(Math.max(0, Math.min(1, offset / maxScroll)) * (total - 1));
      };
      """

    // Scrolls to an in-chapter anchor (footnote, endnote, cross-reference)
    // and lands on the page containing it. Returns the resolved page index,
    // or null when the anchor does not exist so the caller can fall back to the
    // chapter start.
    static func makeScrollToAnchorScript(
      anchor: String,
      paginationLayout: WebPubPaginationLayout
    ) -> String {
      let anchorJSON = WebPubJavaScriptSupport.escapedJSONString(anchor)
      return """
        (function() {
          \(paginationRuntimeScript(paginationLayout: paginationLayout))
          var id = \(anchorJSON);
          try { id = decodeURIComponent(id); } catch (e) {}
          var el = document.getElementById(id);
          if (!el) {
            try { el = document.querySelector('[name="' + id.replace(/"/g, '') + '"]'); } catch (e) { el = null; }
          }
          if (!el) { return null; }
          var metrics = measurePagination();
          var pageWidth = metrics.pageWidth;
          if (pageWidth <= 0) { return null; }
          var fragments = el.getClientRects();
          var rect = fragments.length ? fragments[0] : el.getBoundingClientRect();
          var logical;
          if (reverseScrollLeft) {
            // Later columns lie left of the right-hand origin (negative
            // physical x once the transform shift is removed), so the logical
            // distance is measured back from the active offset.
            logical = pageWidth + currentLogicalOffset() - rect.right;
          } else {
            logical = rect.left + (window.pageXOffset || (document.documentElement ? document.documentElement.scrollLeft : 0) || 0);
          }
          var page = Math.max(0, Math.floor(logical / pageWidth));
          var maxPage = Math.max(0, Math.round(metrics.maxScroll / pageWidth));
          if (page > maxPage) { page = maxPage; }
          scrollToLogicalOffset(pageWidth * page, false);
          return page;
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
          try { id = decodeURIComponent(id); } catch (e) {}
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
      var metrics = measurePagination();
      var total = Math.max(1, Math.ceil(metrics.currentWidth / metrics.pageWidth - 0.002));
      return {
        totalPages: total,
        currentPage: Math.max(0, Math.min(total - 1, Math.round(currentLogicalOffset() / metrics.pageWidth)))
      };
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
          return 0;
        }
        var root = document.documentElement;
        var left = window.pageXOffset || (root ? root.scrollLeft : 0) || 0;
        return Math.abs(left);
      };
      var measurePagination = function() {
        var root = document.documentElement;
        var body = document.body;
        var previousOffset = currentLogicalOffset();
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

  }
#endif
