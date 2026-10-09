#if os(iOS) || os(macOS)
  import SwiftUI

  struct PdfControlsOverlayView: View {
    @Binding var readingDirection: ReadingDirection
    @Binding var pagePresentation: PdfPagePresentation
    @Binding var soloCoverPage: Bool

    @Binding var showingPageJumpSheet: Bool
    @Binding var showingSearchSheet: Bool
    @Binding var showingTOCSheet: Bool
    @Binding var showingReaderSettingsSheet: Bool
    @Binding var showingDetailSheet: Bool

    let currentBook: Book?
    let fallbackTitle: String
    let incognito: Bool
    let currentPage: Int
    let pageCount: Int
    let hasTOC: Bool
    let canSearch: Bool
    let controlsVisible: Bool
    let showGradientBackground: Bool
    let showProgressBarWhileReading: Bool
    let onDismiss: () -> Void

    @Namespace private var progressBarNamespace

    private static let scrimExtensionHeight: CGFloat = 120
    private static let topScrimPeakOpacity: Double = 0.65
    private static let bottomScrimPeakOpacity: Double = 0.7
    private static let topBarHideOffset: CGFloat = 300
    private static let bottomBarHideOffset: CGFloat = 380

    private var animation: Animation {
      .appCurve(0.2)
    }

    // Bar visibility: opacity rides a quick curve while the slide springs, so a
    // gesture-driven toggle inherits velocity instead of easing uniformly.
    private var visibilityAnimation: Animation {
      .appCurve(0.3)
    }

    private var controlsOpacity: Double {
      controlsVisible ? 1 : 0
    }

    private var progress: Double {
      guard pageCount > 0 else { return 0 }
      let clampedPage = min(max(currentPage, 1), pageCount)
      return Double(clampedPage) / Double(pageCount)
    }

    private var displayedCurrentPage: String {
      guard pageCount > 0 else { return "0" }
      if currentPage > pageCount {
        return String(localized: "reader.page.end")
      }
      return String(max(1, currentPage))
    }

    var body: some View {
      ZStack(alignment: .bottom) {
        topControlsLayer
        bottomControlsLayer
        hiddenProgressLayer
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .animation(visibilityAnimation, value: controlsVisible)
      .animation(visibilityAnimation, value: showProgressBarWhileReading)
      .allowsHitTesting(controlsVisible)
    }

    @ViewBuilder
    private var topControlsLayer: some View {
      VStack(spacing: 0) {
        topBar
          .offset(y: controlsVisible ? 0 : -Self.topBarHideOffset)
          .animation(.appSpring, value: controlsVisible)
          .opacity(controlsOpacity)
          .animation(visibilityAnimation, value: controlsOpacity)
          .accessibilityHidden(!controlsVisible)

        Spacer(minLength: 0)
      }
    }

    @ViewBuilder
    private var bottomControlsLayer: some View {
      if showProgressBarWhileReading {
        // Kept conditional so the always-on mini progress bar keeps its
        // matched-geometry morph against the full bar.
        if controlsVisible {
          visibleBottomOverlayBar
            .transition(.opacity)
        }
      } else {
        visibleBottomOverlayBar
          .offset(y: controlsVisible ? 0 : Self.bottomBarHideOffset)
          .animation(.appSpring, value: controlsVisible)
          .opacity(controlsOpacity)
          .animation(visibilityAnimation, value: controlsOpacity)
          .accessibilityHidden(!controlsVisible)
      }
    }

    @ViewBuilder
    private var hiddenProgressLayer: some View {
      if !controlsVisible && showProgressBarWhileReading {
        hiddenProgressBar
          .transition(.opacity)
      }
    }

    private var topBar: some View {
      VStack(spacing: 0) {
        HStack {
          #if !os(macOS)
            Button {
              onDismiss()
            } label: {
              Image(systemName: AppIcon.close)
                .contentShape(Circle())
            }
            .accessibilityLabel(Text("Close"))
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .readerControlButtonStyle()
          #endif

          Spacer()

          if !titleText.isEmpty {
            Button {
              guard currentBook != nil else { return }
              showingDetailSheet = true
            } label: {
              HStack(spacing: 4) {
                if incognito {
                  Image(systemName: "eye.slash.fill")
                    .font(.callout)
                }

                if let subtitleText {
                  VStack(alignment: incognito ? .leading : .center, spacing: 4) {
                    Text(titleText)
                      .lineLimit(1)
                    Text(subtitleText)
                      .foregroundStyle(.secondary)
                      .font(.caption)
                      .lineLimit(1)
                  }
                } else {
                  Text(titleText)
                    .lineLimit(2)
                }
              }
              .padding(.vertical, 2)
              .padding(.horizontal)
              .readerHeaderTitleControlFrame()
              .contentShape(Capsule())
            }
            .optimizedControlSize()
            .readerControlButtonStyle()
          }

          Spacer()

          #if !os(macOS)
            Menu {
              menuContent()
            } label: {
              Image(systemName: AppIcon.more)
                .padding(4)
                .contentShape(Circle())
            }
            .accessibilityLabel(Text("Current Reading Options"))
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .readerControlButtonStyle()
          #endif
        }
        .allowsHitTesting(true)
        .padding()
        .iPadIgnoresSafeArea(paddingTop: 24)
        .contentShape(Rectangle())

        if showGradientBackground {
          Color.clear
            .frame(height: Self.scrimExtensionHeight)
            .allowsHitTesting(false)
        }
      }
      .background {
        gradientBackground(
          startPoint: .top,
          endPoint: .bottom,
          peakOpacity: Self.topScrimPeakOpacity
        )
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
      }
    }

    private var visibleBottomOverlayBar: some View {
      VStack(spacing: 0) {
        if showGradientBackground {
          Color.clear
            .frame(height: Self.scrimExtensionHeight)
            .allowsHitTesting(false)
        }

        bottomOverlayContent(showPageButton: true)
          .padding()
          .contentShape(Rectangle())
      }
      .background {
        gradientBackground(
          startPoint: .bottom,
          endPoint: .top,
          peakOpacity: Self.bottomScrimPeakOpacity
        )
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
      }
    }

    private var hiddenProgressBar: some View {
      ZStack(alignment: .bottom) {
        Color.clear
        bottomOverlayContent(
          showPageButton: false,
          progressHorizontalPadding: PlatformHelper.bottomEdgeHorizontalPadding
        )
        .frame(maxWidth: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .readerIgnoresSafeArea()
      .allowsHitTesting(false)
    }

    private func bottomOverlayContent(
      showPageButton: Bool,
      progressHorizontalPadding: CGFloat = 0
    ) -> some View {
      VStack(spacing: 12) {
        if showPageButton {
          HStack {
            Spacer(minLength: 0)

            Button {
              guard pageCount > 0 else { return }
              showingPageJumpSheet = true
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "bookmark")
                Text("\(displayedCurrentPage) / \(pageCount)")
                  .monospacedDigit()
                  .contentTransition(.numericText())
              }
              .contentShape(Capsule())
            }
            .readerControlButtonStyle()
            .disabled(pageCount <= 0)
            .animation(animation, value: displayedCurrentPage)
            .animation(animation, value: pageCount)

            Spacer(minLength: 0)
          }
          .optimizedControlSize()
          .allowsHitTesting(true)
        }

        progressBar
          .padding(.horizontal, progressHorizontalPadding)
      }
      .animation(animation, value: progressHorizontalPadding)
    }

    @ViewBuilder
    private var progressBar: some View {
      let bar = ReadingProgressBar(progress: progress, type: .reader)
        .scaleEffect(x: readingDirection == .rtl ? -1 : 1, y: 1)

      if showProgressBarWhileReading {
        bar.matchedGeometryEffect(id: "readerProgressBar", in: progressBarNamespace)
      } else {
        bar
      }
    }

    @ViewBuilder
    private func menuContent() -> some View {
      Section {
        Picker(selection: $readingDirection) {
          ForEach(ReadingDirection.pdfAvailableCases, id: \.self) { direction in
            Label(direction.displayName, systemImage: direction.icon)
              .tag(direction)
          }
        } label: {
          Label(String(localized: "Reading Direction"), systemImage: readingDirection.icon)
        }
        .pickerStyle(.menu)

        Picker(selection: $pagePresentation) {
          ForEach(PdfPagePresentation.allCases, id: \.self) { presentation in
            Label(presentation.displayName, systemImage: presentation.icon)
              .tag(presentation)
          }
        } label: {
          Label(String(localized: "Page Presentation"), systemImage: pagePresentation.icon)
        }
        .pickerStyle(.menu)

        if pagePresentation.supportsCoverSolo {
          pageSolo()
        }
      } header: {
        Text(String(localized: "Current Reading Options"))
      }

      Button {
        showingReaderSettingsSheet = true
      } label: {
        Label(String(localized: "Reader Settings"), systemImage: AppIcon.settings)
      }

      Section {
        if hasTOC {
          Button {
            showingTOCSheet = true
          } label: {
            Label(String(localized: "Table of Contents"), systemImage: "list.bullet")
          }
        }

        Button {
          guard pageCount > 0 else { return }
          showingPageJumpSheet = true
        } label: {
          Label(String(localized: "Jump to Page"), systemImage: AppIcon.pageJump)
        }
        .disabled(pageCount <= 0)

        Button {
          showingSearchSheet = true
        } label: {
          Label(String(localized: "Search"), systemImage: AppIcon.search)
        }
        .disabled(!canSearch)
      } header: {
        Text(String(localized: "Page Navigation"))
      }
    }

    @ViewBuilder
    private func pageSolo() -> some View {
      Button {
        soloCoverPage.toggle()
      } label: {
        Label(
          String(localized: "Solo Cover Page"),
          systemImage: soloCoverPage ? "checkmark.rectangle.portrait" : "rectangle.portrait"
        )
      }
    }

    @ViewBuilder
    private func gradientBackground(
      startPoint: UnitPoint,
      endPoint: UnitPoint,
      peakOpacity: Double
    ) -> some View {
      if showGradientBackground {
        LinearGradient(
          gradient: Gradient(stops: [
            .init(color: Color.black.opacity(peakOpacity), location: 0),
            .init(color: Color.black.opacity(peakOpacity * 0.45), location: 0.55),
            .init(color: Color.clear, location: 1),
          ]),
          startPoint: startPoint,
          endPoint: endPoint
        )
      }
    }

    private var titleText: String {
      if let currentBook {
        if currentBook.oneshot {
          return currentBook.metadata.title
        }

        return "#\(currentBook.metadata.number) - \(currentBook.metadata.title)"
      }

      return fallbackTitle
    }

    private var subtitleText: String? {
      guard let currentBook else { return nil }
      guard !currentBook.oneshot else { return nil }
      return currentBook.seriesTitle
    }
  }
#endif
