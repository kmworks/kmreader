#if os(iOS) || os(tvOS)
  import SwiftUI
  import UIKit

  struct ScrollPageView: UIViewRepresentable {
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

    private var shouldDisableScrollInteraction: Bool {
      #if os(tvOS)
        true
      #else
        viewModel.isZoomed
      #endif
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
      let layout = UICollectionViewFlowLayout()
      layout.scrollDirection = mode.isVertical ? .vertical : .horizontal
      layout.minimumLineSpacing = 0
      layout.minimumInteritemSpacing = 0

      let collectionView = NativePagedLayoutAwareCollectionView(
        frame: .zero,
        collectionViewLayout: layout
      )
      collectionView.delegate = context.coordinator
      collectionView.dataSource = context.coordinator
      collectionView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      collectionView.showsHorizontalScrollIndicator = false
      collectionView.showsVerticalScrollIndicator = false
      collectionView.contentInsetAdjustmentBehavior = .never
      collectionView.bounces = false
      collectionView.isPrefetchingEnabled = false
      collectionView.semanticContentAttribute = .forceLeftToRight

      #if os(iOS) || os(macOS)
        collectionView.isPagingEnabled = true
        collectionView.scrollsToTop = false
      #endif

      collectionView.register(
        NativePagedPageCell.self,
        forCellWithReuseIdentifier: Coordinator.pageCellReuseIdentifier
      )
      collectionView.register(
        NativePagedEndCell.self,
        forCellWithReuseIdentifier: Coordinator.endCellReuseIdentifier
      )

      let singleTapGesture = UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleSingleTap(_:))
      )
      singleTapGesture.numberOfTapsRequired = 1
      singleTapGesture.cancelsTouchesInView = false
      singleTapGesture.delegate = context.coordinator
      collectionView.addGestureRecognizer(singleTapGesture)
      context.coordinator.singleTapGesture = singleTapGesture

      let doubleTapGesture = UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleDoubleTap(_:))
      )
      doubleTapGesture.numberOfTapsRequired = 2
      doubleTapGesture.cancelsTouchesInView = false
      doubleTapGesture.delegate = context.coordinator
      singleTapGesture.require(toFail: doubleTapGesture)
      singleTapGesture.require(toFail: collectionView.panGestureRecognizer)
      collectionView.addGestureRecognizer(doubleTapGesture)
      context.coordinator.doubleTapGesture = doubleTapGesture

      let longPressGesture = UILongPressGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleLongPress(_:))
      )
      longPressGesture.cancelsTouchesInView = false
      longPressGesture.delegate = context.coordinator
      singleTapGesture.require(toFail: longPressGesture)
      collectionView.addGestureRecognizer(longPressGesture)

      context.coordinator.collectionView = collectionView
      context.coordinator.applyDoubleTapGestureState()
      collectionView.onDidLayout = { [weak coordinator = context.coordinator] in
        coordinator?.handleCollectionViewLayout()
      }
      collectionView.shouldBeginPan = { [weak coordinator = context.coordinator] pan in
        coordinator?.shouldBeginPaging(with: pan) ?? true
      }
      return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
      context.coordinator.update(parent: self, collectionView: collectionView)
      collectionView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      collectionView.semanticContentAttribute = .forceLeftToRight
      collectionView.isScrollEnabled = !shouldDisableScrollInteraction
      if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
        let targetDirection: UICollectionView.ScrollDirection = mode.isVertical ? .vertical : .horizontal
        if layout.scrollDirection != targetDirection {
          layout.scrollDirection = targetDirection
          layout.invalidateLayout()
        }
      }
    }

    static func dismantleUIView(_ uiView: UICollectionView, coordinator: Coordinator) {
      coordinator.synchronizeCurrentPositionBeforeTeardown(in: uiView)
      coordinator.teardown()
    }
  }
#endif
