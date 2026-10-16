#if os(macOS)
  import AppKit
  import SwiftUI

  struct ScrollPageView: NSViewRepresentable {
    let mode: PageViewMode
    let viewportSize: CGSize
    let readingDirection: ReadingDirection
    let splitWidePageMode: SplitWidePageMode
    let navigationAnimationDuration: TimeInterval
    let renderConfig: ReaderRenderConfig
    @Bindable var viewModel: ReaderViewModel
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler

    init(
      mode: PageViewMode,
      viewportSize: CGSize,
      readingDirection: ReadingDirection,
      splitWidePageMode: SplitWidePageMode,
      navigationAnimationDuration: TimeInterval = 0.3,
      renderConfig: ReaderRenderConfig,
      viewModel: ReaderViewModel,
      readListContext: ReaderReadListContext?,
      onDismiss: @escaping () -> Void,
      onTapZoneTap: @escaping ReaderTapZoneTapHandler
    ) {
      self.mode = mode
      self.viewportSize = viewportSize
      self.readingDirection = readingDirection
      self.splitWidePageMode = splitWidePageMode
      self.navigationAnimationDuration = navigationAnimationDuration
      self.renderConfig = renderConfig
      self.viewModel = viewModel
      self.readListContext = readListContext
      self.onDismiss = onDismiss
      self.onTapZoneTap = onTapZoneTap
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
      let layout = NSCollectionViewFlowLayout()
      layout.scrollDirection = mode.isVertical ? .vertical : .horizontal
      layout.minimumLineSpacing = 0
      layout.minimumInteritemSpacing = 0

      let collectionView = NativePagedLayoutAwareCollectionView()
      collectionView.collectionViewLayout = layout
      collectionView.delegate = context.coordinator
      collectionView.dataSource = context.coordinator
      collectionView.backgroundColors = [NSColor(renderConfig.readerBackground.color)]
      collectionView.isSelectable = false
      collectionView.userInterfaceLayoutDirection = .leftToRight
      collectionView.register(
        NativePagedPageCell.self,
        forItemWithIdentifier: NSUserInterfaceItemIdentifier(Coordinator.pageCellReuseIdentifier)
      )
      collectionView.register(
        NativePagedEndCell.self,
        forItemWithIdentifier: NSUserInterfaceItemIdentifier(Coordinator.endCellReuseIdentifier)
      )

      let scrollView = NSScrollView()
      scrollView.documentView = collectionView
      scrollView.hasVerticalScroller = false
      scrollView.hasHorizontalScroller = false
      scrollView.backgroundColor = NSColor(renderConfig.readerBackground.color)
      scrollView.drawsBackground = true
      scrollView.contentView.postsBoundsChangedNotifications = true

      let clickGesture = NSClickGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleClick(_:))
      )
      clickGesture.numberOfClicksRequired = 1
      clickGesture.delegate = context.coordinator
      scrollView.addGestureRecognizer(clickGesture)

      let doubleClickGesture = NSClickGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleDoubleClick(_:))
      )
      doubleClickGesture.numberOfClicksRequired = 2
      doubleClickGesture.delegate = context.coordinator
      scrollView.addGestureRecognizer(doubleClickGesture)

      let longPressGesture = NSPressGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleLongPress(_:))
      )
      longPressGesture.delegate = context.coordinator
      scrollView.addGestureRecognizer(longPressGesture)
      context.coordinator.longPressGesture = longPressGesture

      collectionView.frame = CGRect(origin: .zero, size: scrollView.contentView.bounds.size)
      collectionView.autoresizingMask = [.width, .height]

      context.coordinator.scrollView = scrollView
      context.coordinator.collectionView = collectionView
      context.coordinator.installObservers()
      collectionView.onDidLayout = { [weak coordinator = context.coordinator] in
        coordinator?.handleCollectionViewLayout()
      }

      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      guard let collectionView = scrollView.documentView as? NSCollectionView else { return }

      collectionView.backgroundColors = [NSColor(renderConfig.readerBackground.color)]
      collectionView.userInterfaceLayoutDirection = .leftToRight

      if let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
        let targetDirection: NSCollectionView.ScrollDirection = mode.isVertical ? .vertical : .horizontal
        if layout.scrollDirection != targetDirection {
          layout.scrollDirection = targetDirection
          layout.invalidateLayout()
        }
      }

      context.coordinator.update(parent: self, scrollView: scrollView, collectionView: collectionView)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
      coordinator.synchronizeCurrentPositionBeforeTeardown(in: nsView)
      coordinator.teardown()
    }
  }
#endif
