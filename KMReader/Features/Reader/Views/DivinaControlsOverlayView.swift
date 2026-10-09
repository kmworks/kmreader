//
// DivinaControlsOverlayView.swift
//
//

import SwiftUI

struct DivinaControlsOverlayView: View {
  @Binding var readingDirection: ReadingDirection
  @Binding var pageLayout: PageLayout
  @Binding var isolateCoverPage: Bool
  @Binding var splitWidePageMode: SplitWidePageMode
  @Binding var rotation: ReaderRotation

  @Binding var showingPageJumpSheet: Bool
  @Binding var showingTOCSheet: Bool
  @Binding var showingReaderSettingsSheet: Bool
  @Binding var showingDetailSheet: Bool

  let viewModel: ReaderViewModel
  let currentBook: Book?
  let dualPage: Bool
  let incognito: Bool
  let onDismiss: () -> Void
  let previousBook: Book?
  let nextBook: Book?
  let onPreviousBook: ((String) -> Void)?
  let onNextBook: ((String) -> Void)?
  let controlsVisible: Bool
  let showingControls: Bool
  let showGradientBackground: Bool
  let showProgressBarWhileReading: Bool
  let showPageDimensionWarning: Bool

  @Namespace private var progressBarNamespace
  @State private var showingPageDimensionWarning = false
  @State private var pageDimensionWarningDismissed = false

  #if os(tvOS)
    private enum ControlFocus: Hashable {
      case close
      case title
      case pageDimensionWarning
      case settings
      case pageNumber
    }
    @FocusState private var focusedControl: ControlFocus?
  #endif

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

  private var currentSegmentBookId: String? {
    currentBook?.id
  }

  private var currentPageID: ReaderPageID? {
    viewModel.currentReaderPage?.id
  }

  private var currentSegmentPageCount: Int {
    guard let currentSegmentBookId else {
      return viewModel.pageCount
    }
    return viewModel.pageCount(forSegmentBookId: currentSegmentBookId)
  }

  private var currentSegmentProgressPage: Int {
    guard let currentSegmentBookId else { return 0 }
    guard currentSegmentPageCount > 0 else { return 0 }
    if viewModel.currentViewItem()?.isEnd == true {
      return currentSegmentPageCount
    }
    let currentPageNumber = viewModel.currentPageNumber(inSegmentBookId: currentSegmentBookId) ?? 1
    return min(max(currentPageNumber, 1), currentSegmentPageCount)
  }

  private var progress: Double {
    guard currentSegmentPageCount > 0 else { return 0 }
    return Double(currentSegmentProgressPage) / Double(currentSegmentPageCount)
  }

  private var displayedCurrentPage: String {
    guard currentSegmentPageCount > 0 else { return "0" }
    if viewModel.isShowingEndPage {
      return String(localized: "reader.page.end")
    }
    if dualPage, let pair = viewModel.currentViewItem()?.pagePairIDs {
      return displayPagePair(first: pair.first, second: pair.second)
    }
    guard let currentPageID else { return "0" }
    return String(displayPageNumber(for: currentPageID))
  }

  private func displayPagePair(first: ReaderPageID, second: ReaderPageID?) -> String {
    let firstPageNumber = displayPageNumber(for: first)
    guard let second else { return "\(firstPageNumber)" }
    let secondPageNumber = displayPageNumber(for: second)
    if readingDirection == .rtl {
      return "\(secondPageNumber),\(firstPageNumber)"
    }
    return "\(firstPageNumber),\(secondPageNumber)"
  }

  private func displayPageNumber(for pageID: ReaderPageID) -> Int {
    viewModel.displayPageNumber(for: pageID) ?? pageID.pageNumber + 1
  }

  private var enableDualPageOptions: Bool {
    return readingDirection != .webtoon && readingDirection != .vertical && pageLayout.supportsDualPageOptions
  }

  private var pageIsolationActions: [ReaderPageIsolationActions.Action] {
    ReaderPageIsolationActions.resolve(
      supportsDualPageOptions: enableDualPageOptions,
      dualPage: dualPage,
      readingDirection: readingDirection,
      currentPageID: currentPageID,
      currentPairIDs: viewModel.currentViewItem()?.pagePairIDs,
      isCurrentPageWide: viewModel.isCurrentPageWide,
      isCurrentPageIsolated: viewModel.isCurrentPageIsolated,
      displayPageNumber: displayPageNumber(for:)
    )
  }

  #if os(iOS) || os(macOS)
    private func sharePages(ids: [ReaderPageID]) {
      Task {
        let originals = await withTaskGroup(of: (Int, PlatformImage?).self) { group in
          for (index, pageID) in ids.enumerated() {
            group.addTask {
              await (index, viewModel.originalPageImage(for: pageID))
            }
          }
          var loaded: [(Int, PlatformImage?)] = []
          for await result in group {
            loaded.append(result)
          }
          return loaded.sorted { $0.0 < $1.0 }
        }

        var images: [PlatformImage] = []
        var names: [String] = []
        for (index, original) in originals {
          let pageID = ids[index]
          guard let page = viewModel.page(for: pageID) else { continue }
          if let image = original ?? viewModel.preloadedImage(for: pageID) {
            images.append(image)
            names.append(page.fileName)
          }
        }

        guard !images.isEmpty else { return }
        await ImageShareHelper.shareMultiple(images: images, fileNames: names)
      }
    }

    private func sharePage(id: ReaderPageID) {
      sharePages(ids: [id])
    }

    private var pageFormat: String {
      String(localized: "Page %d")
    }

  #endif

  private static let scrimExtensionHeight: CGFloat = 120
  private static let topScrimPeakOpacity: Double = 0.65
  private static let bottomScrimPeakOpacity: Double = 0.7
  private static let topBarHideOffset: CGFloat = 300
  private static let bottomBarHideOffset: CGFloat = 380

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
    .alert(
      "reader.pageDimensions.warning.title",
      isPresented: $showingPageDimensionWarning
    ) {
      Button("Dismiss") {
        pageDimensionWarningDismissed = true
      }
    } message: {
      Text("reader.missingPageDimensions.alert")
    }
    #if os(tvOS)
      .onAppear {
        if showingControls {
          focusedControl = .close
        }
      }
      .onChange(of: showingControls) { _, newValue in
        focusedControl = newValue ? .close : nil
      }
      .onChange(of: focusedControl) { _, newValue in
        if showingControls && newValue == nil {
          focusedControl = .close
        }
      }
      .focusSection()
    #endif
  }

  private var bottomControlsTransition: AnyTransition {
    guard showProgressBarWhileReading else {
      return .move(edge: .bottom).combined(with: .opacity)
    }
    return .opacity
  }

  @ViewBuilder
  private var topControlsLayer: some View {
    VStack(spacing: 0) {
      #if os(tvOS)
        if controlsVisible {
          topBar
            .transition(
              .move(edge: .top)
                .combined(with: .opacity)
            )
        }
      #else
        topBar
          .offset(y: controlsVisible ? 0 : -Self.topBarHideOffset)
          .animation(.appSpring, value: controlsVisible)
          .opacity(controlsOpacity)
          .animation(visibilityAnimation, value: controlsOpacity)
          .accessibilityHidden(!controlsVisible)
      #endif

      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private var bottomControlsLayer: some View {
    #if os(tvOS)
      if controlsVisible {
        visibleBottomOverlayBar
          .transition(bottomControlsTransition)
      }
    #else
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
    #endif
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
          #if os(tvOS)
            .focused($focusedControl, equals: .close)
            .id("closeButton")
          #endif
        #endif

        Spacer()

        if let book = currentBook {
          Button {
            showingDetailSheet = true
          } label: {
            HStack(spacing: 4) {
              if incognito {
                Image(systemName: "eye.slash.fill")
                  .font(.callout)
              }
              VStack(alignment: incognito ? .leading : .center, spacing: 4) {
                if book.oneshot {
                  Text(book.metadata.title)
                    .lineLimit(2)
                } else {
                  Text("#\(book.metadata.number) - \(book.metadata.title)")
                    .lineLimit(1)
                  Text(book.seriesTitle)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .lineLimit(1)
                }
              }
            }
            .padding(.vertical, 2)
            .padding(.horizontal)
            .readerHeaderTitleControlFrame()
            .contentShape(Capsule())
          }
          .optimizedControlSize()
          .readerControlButtonStyle()
          #if os(tvOS)
            .focused($focusedControl, equals: .title)
            .id("titleLabel")
          #endif
        }

        if showPageDimensionWarning && !pageDimensionWarningDismissed {
          Button {
            showingPageDimensionWarning = true
          } label: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.yellow)
              .contentShape(Circle())
          }
          .accessibilityLabel(Text("reader.pageDimensions.warning.title"))
          .buttonBorderShape(.circle)
          .controlSize(.large)
          .readerControlButtonStyle()
          #if os(tvOS)
            .focused($focusedControl, equals: .pageDimensionWarning)
          #endif
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
          #if os(tvOS)
            .focused($focusedControl, equals: .settings)
          #endif
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
            showingPageJumpSheet = true
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "bookmark")
              Text("\(displayedCurrentPage) / \(currentSegmentPageCount)")
                .monospacedDigit()
                .contentTransition(.numericText())
            }
            .contentShape(Capsule())
          }
          .readerControlButtonStyle()
          .disabled(!viewModel.hasPages)
          #if os(tvOS)
            .focused($focusedControl, equals: .pageNumber)
          #endif
          .animation(animation, value: displayedCurrentPage)
          .animation(animation, value: currentSegmentPageCount)

          Spacer(minLength: 0)
        }
        .optimizedControlSize()
        .allowsHitTesting(true)
      }

      progressBar
        .padding(.horizontal, progressHorizontalPadding)
        .animation(animation, value: progress)
        .animation(animation, value: progressHorizontalPadding)
    }
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
        ForEach(ReadingDirection.availableCases, id: \.self) { direction in
          Label(direction.displayName, systemImage: direction.icon)
            .tag(direction)
        }
      } label: {
        Label(String(localized: "Reading Direction"), systemImage: readingDirection.icon)
      }
      .pickerStyle(.menu)

      if readingDirection != .webtoon && readingDirection != .vertical {
        Picker(selection: $pageLayout) {
          ForEach(PageLayout.allCases, id: \.self) { layout in
            Label(layout.displayName, systemImage: layout.icon)
              .tag(layout)
          }
        } label: {
          Label(String(localized: "Page Layout"), systemImage: pageLayout.icon)
        }
        .pickerStyle(.menu)
      }

      if readingDirection != .webtoon {
        Picker(selection: $splitWidePageMode) {
          ForEach(SplitWidePageMode.allCases, id: \.self) { mode in
            Label(mode.displayName, systemImage: mode.icon).tag(mode)
          }
        } label: {
          Label(String(localized: "Split Wide Pages"), systemImage: splitWidePageMode.icon)
        }
        .pickerStyle(.menu)

        Picker(selection: $rotation) {
          ForEach(ReaderRotation.allCases, id: \.self) { rotation in
            Text(verbatim: rotation.displayName).tag(rotation)
          }
        } label: {
          Label(String(localized: "Page Rotation"), systemImage: "rotate.right")
        }
        .pickerStyle(.menu)
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
      pageNavigation()
    } header: {
      Text(String(localized: "Page Navigation"))
    }

    Section {
      bookNavigation()
    } header: {
      Text(String(localized: "Book Navigation"))
    }

    #if os(iOS) || os(macOS)
      if currentPageID != nil {
        Section {
          if dualPage, let pair = viewModel.currentViewItem()?.pagePairIDs {
            pageActionsMenu(for: pair.first)
            if let second = pair.second {
              pageActionsMenu(for: second)
            }
          } else if let currentPageID {
            pageActionsMenu(for: currentPageID)
          } else {
            EmptyView()
          }
        } header: {
          Text(String(localized: "Current Page"))
        }
      }
    #endif
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

  @ViewBuilder
  private func pageNavigation() -> some View {
    if !viewModel.tableOfContents.isEmpty {
      Button {
        showingTOCSheet = true
      } label: {
        Label(String(localized: "Table of Contents"), systemImage: "list.bullet")
      }
    }
    Button {
      guard viewModel.hasPages else { return }
      showingPageJumpSheet = true
    } label: {
      Label(String(localized: "Jump to Page"), systemImage: AppIcon.pageJump)
    }
    .disabled(!viewModel.hasPages)
  }

  @ViewBuilder
  private func bookNavigation() -> some View {
    if let previousBook, let onPreviousBook {
      let previousNumber =
        previousBook.metadata.number.isEmpty
        ? nil
        : previousBook.metadata.number
      Button {
        onPreviousBook(previousBook.id)
      } label: {
        Label(
          "\(String(localized: "reader.previousBook")) #\(previousNumber ?? "-")",
          systemImage: "chevron.left"
        )
      }
    }

    if let nextBook, let onNextBook {
      let nextNumber =
        nextBook.metadata.number.isEmpty
        ? nil
        : nextBook.metadata.number
      Button {
        onNextBook(nextBook.id)
      } label: {
        Label(
          "\(String(localized: "reader.nextBook")) #\(nextNumber ?? "-")",
          systemImage: "chevron.right"
        )
      }
    }
  }

  #if os(iOS) || os(macOS)
    @ViewBuilder
    private func pageActionsMenu(for pageID: ReaderPageID) -> some View {
      let displayedPageNumber = displayPageNumber(for: pageID)
      Menu {
        Button {
          sharePage(id: pageID)
        } label: {
          Label(String(localized: "Share"), systemImage: AppIcon.share)
        }

        if let isolationAction = pageIsolationAction(for: pageID) {
          Button {
            viewModel.toggleIsolatePage(isolationAction.pageID)
          } label: {
            Label(pageIsolationMenuTitle(for: isolationAction), systemImage: isolationAction.systemImage)
          }
        }
      } label: {
        Label(
          String.localizedStringWithFormat(pageFormat, displayedPageNumber),
          systemImage: "doc"
        )
      }
    }

    private func pageIsolationAction(for pageID: ReaderPageID) -> ReaderPageIsolationActions.Action? {
      pageIsolationActions.first { $0.pageID == pageID }
    }

    private func pageIsolationMenuTitle(for action: ReaderPageIsolationActions.Action) -> String {
      if action.title == String(localized: "Cancel Isolation") {
        return action.title
      }
      return String(localized: "Isolate")
    }
  #endif
}
