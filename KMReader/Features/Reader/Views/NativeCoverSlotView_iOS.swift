#if os(iOS) || os(tvOS)
  import UIKit
  import SwiftUI

  @MainActor
  final class NativeCoverSlotView: UIView {
    private struct Configuration: Equatable {
      let item: ReaderViewItem?
      let isVisible: Bool
      let screenSize: CGSize
      let readingDirection: ReadingDirection
      let splitWidePageMode: SplitWidePageMode
      let renderConfig: ReaderRenderConfig
      let readListContext: ReaderReadListContext?
      let isPlaybackActive: Bool
      let tracksGlobalZoomState: Bool
    }

    private let pageContentView = NativePagedPageContentView()
    private let endPageContentView = NativeEndPageContentView()

    private weak var viewModel: ReaderViewModel?
    private var lastConfiguration: Configuration?
    private var representedItem: ReaderViewItem?
    private var currentScreenSize: CGSize = .zero
    private var readingDirection: ReadingDirection = .ltr
    private var splitWidePageMode: SplitWidePageMode = .auto
    private var renderConfig = ReaderRenderConfig(
      tapZoneMode: .defaultLayout,
      tapZoneInversionMode: .auto,
      showPageNumber: true,
      showPageShadow: true,
      readerBackground: .system,
      enableLiveText: false,
      enableImageContextMenu: false,
      supportsPageIsolationActions: false,
      doubleTapZoomScale: 3.0,
      doubleTapZoomMode: .enabled
    )
    private var readListContext: ReaderReadListContext?
    // Not part of `Configuration`: everything the page host reads from it
    // follows fields that are. Its arrival edge applies only on an item
    // change, and its start side comes from the reading direction and split
    // mode; either change forces an apply.
    private var wholeSpread: WholeSpreadPresentation?
    private var isPlaybackActive = false
    private var tracksGlobalZoomState = false
    private var onDismiss: (() -> Void)?

    var item: ReaderViewItem? {
      representedItem
    }

    func forceResetZoom() {
      pageContentView.forceResetZoom()
    }

    func panWholeSpread(to edge: ReaderSpreadEdge, animated: Bool) {
      pageContentView.panWholeSpread(to: edge, animated: animated)
    }

    func canPanWholeSpread(forHorizontalDrag translationX: CGFloat) -> Bool {
      !pageContentView.isHidden && pageContentView.canPanWholeSpread(forHorizontalDrag: translationX)
    }

    override init(frame: CGRect) {
      super.init(frame: frame)
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func configure(
      item: ReaderViewItem?,
      wholeSpread: WholeSpreadPresentation?,
      viewModel: ReaderViewModel,
      screenSize: CGSize,
      readingDirection: ReadingDirection,
      splitWidePageMode: SplitWidePageMode,
      renderConfig: ReaderRenderConfig,
      readListContext: ReaderReadListContext?,
      isVisible: Bool,
      isPlaybackActive: Bool,
      tracksGlobalZoomState: Bool,
      onDismiss: @escaping () -> Void
    ) {
      let configuration = Configuration(
        item: item,
        isVisible: isVisible,
        screenSize: screenSize,
        readingDirection: readingDirection,
        splitWidePageMode: splitWidePageMode,
        renderConfig: renderConfig,
        readListContext: readListContext,
        isPlaybackActive: isPlaybackActive,
        tracksGlobalZoomState: tracksGlobalZoomState
      )
      let needsApply =
        self.viewModel !== viewModel
        || lastConfiguration != configuration
        || shouldForceApply(for: configuration)

      self.representedItem = item
      self.viewModel = viewModel
      self.lastConfiguration = configuration
      self.currentScreenSize = screenSize
      self.readingDirection = readingDirection
      self.splitWidePageMode = splitWidePageMode
      self.renderConfig = renderConfig
      self.readListContext = readListContext
      self.wholeSpread = wholeSpread
      self.isPlaybackActive = isPlaybackActive
      self.tracksGlobalZoomState = tracksGlobalZoomState
      self.onDismiss = onDismiss
      guard needsApply else { return }
      applyConfiguration()
      prepareDisplayLayoutIfNeeded()
    }

    func refreshContent() {
      applyConfiguration()
      prepareDisplayLayoutIfNeeded()
    }

    func setPlaybackActive(_ isPlaybackActive: Bool, tracksGlobalZoomState: Bool) {
      self.isPlaybackActive = isPlaybackActive
      self.tracksGlobalZoomState = tracksGlobalZoomState
      if let lastConfiguration {
        self.lastConfiguration = Configuration(
          item: lastConfiguration.item,
          isVisible: lastConfiguration.isVisible,
          screenSize: lastConfiguration.screenSize,
          readingDirection: lastConfiguration.readingDirection,
          splitWidePageMode: lastConfiguration.splitWidePageMode,
          renderConfig: lastConfiguration.renderConfig,
          readListContext: lastConfiguration.readListContext,
          isPlaybackActive: isPlaybackActive,
          tracksGlobalZoomState: tracksGlobalZoomState
        )
      }
      applyConfiguration()
      prepareDisplayLayoutIfNeeded()
    }

    func containsAny(pageIDs: Set<ReaderPageID>) -> Bool {
      guard let representedItem else { return false }
      return representedItem.pageIDs.contains(where: pageIDs.contains)
    }

    func prepareForDismantle() {
      lastConfiguration = nil
      representedItem = nil
      viewModel = nil
      readListContext = nil
      onDismiss = nil
      pageContentView.resetContent()
      endPageContentView.configure(
        previousBook: nil,
        nextBook: nil,
        readListContext: nil,
        readingDirection: .ltr,
        renderConfig: renderConfig,
        onDismiss: nil
      )
    }

    private func setupUI() {
      isHidden = true
      backgroundColor = .clear

      pageContentView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(pageContentView)

      endPageContentView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(endPageContentView)

      NSLayoutConstraint.activate([
        pageContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
        pageContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        pageContentView.topAnchor.constraint(equalTo: topAnchor),
        pageContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        endPageContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
        endPageContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        endPageContentView.topAnchor.constraint(equalTo: topAnchor),
        endPageContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    private func shouldForceApply(for configuration: Configuration) -> Bool {
      guard let item = configuration.item else { return false }
      return item.isEnd
    }

    private func prepareDisplayLayoutIfNeeded() {
      guard bounds.width > 0, bounds.height > 0 else { return }
      UIView.performWithoutAnimation {
        setNeedsLayout()
        layoutIfNeeded()
        pageContentView.setNeedsLayout()
        pageContentView.layoutIfNeeded()
      }
    }

    private func applyConfiguration() {
      guard let viewModel, let representedItem else {
        isHidden = true
        pageContentView.resetContent()
        endPageContentView.isHidden = true
        pageContentView.isHidden = true
        return
      }

      isHidden = false
      backgroundColor = UIColor(renderConfig.readerBackground.color)

      if case .end(let id) = representedItem {
        pageContentView.isHidden = true
        endPageContentView.isHidden = false
        endPageContentView.configure(
          previousBook: viewModel.endPagePreviousBook(forSegmentBookId: id.bookId),
          nextBook: viewModel.nextBook(forSegmentBookId: id.bookId),
          readListContext: readListContext,
          readingDirection: readingDirection,
          renderConfig: renderConfig,
          nextBookOfflineState: viewModel.nextBookOfflineState(forSegmentBookId: id.bookId),
          onDismiss: onDismiss
        )
        return
      }

      endPageContentView.isHidden = true
      pageContentView.isHidden = false
      pageContentView.configure(
        viewModel: viewModel,
        item: representedItem,
        wholeSpread: wholeSpread,
        screenSize: currentScreenSize,
        renderConfig: renderConfig,
        readingDirection: readingDirection,
        splitWidePageMode: splitWidePageMode,
        isPlaybackActive: isPlaybackActive,
        tracksGlobalZoomState: tracksGlobalZoomState
      )
    }
  }
#endif
