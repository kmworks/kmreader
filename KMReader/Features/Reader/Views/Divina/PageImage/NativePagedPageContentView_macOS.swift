#if os(macOS)
  import AppKit
  import SwiftUI

  final class NativePagedPageContentView: NSView {
    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private var pageViews: [NativePageItem] = []

    private weak var viewModel: ReaderViewModel?
    private var currentItem: ReaderViewItem?
    private var currentPageData: [NativePageData] = []
    private var currentScreenSize: CGSize = .zero
    private var currentSplitWidePageMode: SplitWidePageMode = .auto
    private var renderConfig = ReaderRenderConfig(
      tapZoneMode: .defaultLayout,
      tapZoneInversionMode: .auto,
      showPageNumber: true,
      showPageShadow: true,
      readerBackground: .system,
      enableLiveText: false,
      enableImageContextMenu: false,
      supportsPageSoloActions: false,
      doubleTapZoomScale: 3.0,
      doubleTapZoomMode: .enabled
    )
    private var readingDirection: ReadingDirection = .ltr
    private var isPlaybackActive = false
    private var tracksGlobalZoomState = true
    private var isUpdatingMagnification = false

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
      super.layout()
      updatePages()
    }

    func configure(
      viewModel: ReaderViewModel,
      item: ReaderViewItem,
      screenSize: CGSize,
      renderConfig: ReaderRenderConfig,
      readingDirection: ReadingDirection,
      splitWidePageMode: SplitWidePageMode,
      isPlaybackActive: Bool,
      tracksGlobalZoomState: Bool
    ) {
      let itemChanged = currentItem != item

      self.viewModel = viewModel
      self.currentItem = item
      self.currentScreenSize = screenSize
      self.currentSplitWidePageMode = splitWidePageMode
      self.renderConfig = renderConfig
      self.readingDirection = readingDirection
      self.isPlaybackActive = isPlaybackActive
      self.tracksGlobalZoomState = tracksGlobalZoomState
      self.currentPageData = viewModel.nativePageData(
        for: item,
        readingDirection: readingDirection,
        splitWidePageMode: splitWidePageMode,
        isPlaybackActive: isPlaybackActive
      )

      if itemChanged {
        resetMagnification()
      }

      wantsLayer = true
      layer?.backgroundColor = NSColor(renderConfig.readerBackground.color).cgColor
      scrollView.backgroundColor = NSColor(renderConfig.readerBackground.color)
      contentStack.userInterfaceLayoutDirection =
        readingDirection == .rtl ? .rightToLeft : .leftToRight

      updatePages()
    }

    func updatePlaybackActive(_ isPlaybackActive: Bool) {
      guard self.isPlaybackActive != isPlaybackActive else { return }
      self.isPlaybackActive = isPlaybackActive
      guard let viewModel, let currentItem else { return }

      currentPageData = viewModel.nativePageData(
        for: currentItem,
        readingDirection: readingDirection,
        splitWidePageMode: currentSplitWidePageMode,
        isPlaybackActive: isPlaybackActive
      )
      updatePages()
    }

    func resetContent(backgroundColor: NSColor? = nil) {
      viewModel = nil
      currentItem = nil
      currentPageData = []
      currentScreenSize = .zero
      isPlaybackActive = false
      tracksGlobalZoomState = true
      if let backgroundColor {
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        scrollView.backgroundColor = backgroundColor
      }
      pageViews.forEach { $0.prepareForDismantle() }
      resetMagnification()
    }

    private func setupUI() {
      wantsLayer = true

      scrollView.translatesAutoresizingMaskIntoConstraints = false
      scrollView.hasVerticalScroller = false
      scrollView.hasHorizontalScroller = false
      scrollView.allowsMagnification = true
      scrollView.minMagnification = 1.0
      scrollView.maxMagnification = 8.0
      scrollView.backgroundColor = NSColor(renderConfig.readerBackground.color)
      scrollView.drawsBackground = true
      addSubview(scrollView)

      contentStack.orientation = .horizontal
      contentStack.distribution = .fillEqually
      contentStack.spacing = 0
      contentStack.translatesAutoresizingMaskIntoConstraints = false
      scrollView.documentView = contentStack

      NSLayoutConstraint.activate([
        scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        scrollView.topAnchor.constraint(equalTo: topAnchor),
        scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        contentStack.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
      ])

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleMagnificationEnded),
        name: NSScrollView.didEndLiveMagnifyNotification,
        object: scrollView
      )
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    private func updatePages() {
      guard let viewModel else { return }
      let pages = currentPageData
      let canSoloPageFromCurrentPresentation =
        renderConfig.supportsPageSoloActions
        && pages.count == 2
        && Set(pages.map(\.pageID)).count == 2

      if pageViews.count != pages.count {
        pageViews.forEach { view in
          view.prepareForDismantle()
          view.removeFromSuperview()
        }
        pageViews = pages.map { _ in NativePageItem() }
        pageViews.forEach { contentStack.addArrangedSubview($0) }
      }

      let targetHeight = bounds.height > 0 ? bounds.height : currentScreenSize.height

      for (index, data) in pages.enumerated() {
        let image = viewModel.preloadedImage(for: data.pageID)
        pageViews[index].update(
          with: data,
          viewModel: viewModel,
          image: image,
          showPageNumber: renderConfig.showPageNumber,
          showPageShadow: renderConfig.showPageShadow,
          enableLiveText: renderConfig.enableLiveText,
          enableImageContextMenu: renderConfig.enableImageContextMenu,
          supportsPageSoloActions: renderConfig.supportsPageSoloActions,
          canSoloPageFromCurrentPresentation: canSoloPageFromCurrentPresentation,
          background: renderConfig.readerBackground,
          readingDirection: readingDirection,
          displayMode: .fit,
          targetHeight: targetHeight
        )
      }
    }

    private func resetMagnification() {
      isUpdatingMagnification = true
      scrollView.magnification = scrollView.minMagnification
      scrollView.contentView.bounds.origin = .zero
      scrollView.reflectScrolledClipView(scrollView.contentView)
      isUpdatingMagnification = false

      guard tracksGlobalZoomState, let viewModel, viewModel.isZoomed else { return }
      viewModel.isZoomed = false
    }

    @objc private func handleMagnificationEnded() {
      guard tracksGlobalZoomState else { return }
      guard !isUpdatingMagnification else { return }
      guard let viewModel else { return }

      let zoomed = scrollView.magnification > (scrollView.minMagnification + 0.01)
      if viewModel.isZoomed != zoomed {
        viewModel.isZoomed = zoomed
      }
    }
  }
#endif
