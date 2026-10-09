#if os(iOS) || os(tvOS)
  import SwiftUI
  import UIKit

  struct PageScrollView: UIViewRepresentable {
    var viewModel: ReaderViewModel
    let screenSize: CGSize
    let resetID: AnyHashable
    let minScale: CGFloat
    let maxScale: CGFloat
    let displayMode: PageDisplayMode
    let readingDirection: ReadingDirection
    let renderConfig: ReaderRenderConfig
    let initialZoomScale: CGFloat?
    let initialZoomAnchor: CGPoint?
    let initialZoomID: AnyHashable?

    let pages: [NativePageData]

    init(
      viewModel: ReaderViewModel,
      screenSize: CGSize,
      resetID: AnyHashable,
      minScale: CGFloat,
      maxScale: CGFloat,
      displayMode: PageDisplayMode = .fit,
      readingDirection: ReadingDirection,
      renderConfig: ReaderRenderConfig,
      initialZoomScale: CGFloat? = nil,
      initialZoomAnchor: CGPoint? = nil,
      initialZoomID: AnyHashable? = nil,
      pages: [NativePageData]
    ) {
      self.viewModel = viewModel
      self.screenSize = screenSize
      self.resetID = resetID
      self.minScale = minScale
      self.maxScale = maxScale
      self.displayMode = displayMode
      self.readingDirection = readingDirection
      self.renderConfig = renderConfig
      self.initialZoomScale = initialZoomScale
      self.initialZoomAnchor = initialZoomAnchor
      self.initialZoomID = initialZoomID
      self.pages = pages
    }

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
      let scrollView = UIScrollView()
      scrollView.delegate = context.coordinator
      scrollView.minimumZoomScale = minScale
      scrollView.maximumZoomScale = maxScale
      scrollView.showsHorizontalScrollIndicator = false
      scrollView.showsVerticalScrollIndicator = false
      scrollView.contentInsetAdjustmentBehavior = .never

      #if os(tvOS)
        scrollView.isScrollEnabled = false
        scrollView.panGestureRecognizer.isEnabled = false
      #endif

      scrollView.backgroundColor = UIColor(renderConfig.readerBackground.color)

      let contentStack = UIStackView()
      contentStack.axis = .horizontal
      contentStack.distribution = .fillEqually
      contentStack.alignment = .fill
      contentStack.spacing = 0
      contentStack.translatesAutoresizingMaskIntoConstraints = false
      scrollView.addSubview(contentStack)
      context.coordinator.contentStack = contentStack

      NSLayoutConstraint.activate([
        contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
        contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
        contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
        contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
      ])

      context.coordinator.parent = self
      context.coordinator.applyDisplayModeIfNeeded(in: scrollView)
      context.coordinator.setupNativeInteractions(on: scrollView)
      context.coordinator.registerInvalidationObserver()
      return scrollView
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
      coordinator.prepareForDismantle()
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
      context.coordinator.isUpdatingFromSwiftUI = true
      defer {
        DispatchQueue.main.async {
          context.coordinator.isUpdatingFromSwiftUI = false
          context.coordinator.applyInitialZoomIfNeeded(in: uiView)
        }
      }

      context.coordinator.parent = self
      context.coordinator.applyDoubleTapGestureState()
      context.coordinator.applyDisplayModeIfNeeded(in: uiView)
      context.coordinator.updatePages()

      uiView.backgroundColor = UIColor(renderConfig.readerBackground.color)

      if context.coordinator.lastResetID != resetID {
        context.coordinator.lastResetID = resetID
        context.coordinator.lastInitialZoomID = nil
        uiView.setZoomScale(minScale, animated: false)
        uiView.contentOffset = .zero
      }
    }

    @MainActor
    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
      var lastResetID: AnyHashable?
      var lastInitialZoomID: AnyHashable?
      var lastDisplayMode: PageDisplayMode?
      var isUpdatingFromSwiftUI = false

      var parent: PageScrollView!

      weak var contentStack: UIStackView?
      var contentHeightConstraint: NSLayoutConstraint?
      private var pageViews: [NativePageItem] = []
      private var invalidationObserverToken: UUID?
      private weak var doubleTapGesture: UITapGestureRecognizer?

      func registerInvalidationObserver() {
        guard invalidationObserverToken == nil else { return }
        invalidationObserverToken = parent.viewModel.addPagePresentationInvalidationObserver {
          [weak self] _ in
          self?.updatePages()
        }
      }

      func prepareForDismantle() {
        if let token = invalidationObserverToken {
          parent?.viewModel.removePagePresentationInvalidationObserver(token)
          invalidationObserverToken = nil
        }
        pageViews.forEach { view in
          view.prepareForDismantle()
          view.removeFromSuperview()
        }
        pageViews.removeAll()
      }

      func updatePages() {
        guard let stack = contentStack else { return }
        let pages = parent.pages
        let canSoloPageFromCurrentPresentation =
          parent.renderConfig.supportsPageSoloActions
          && pages.count == 2
          && Set(pages.map(\.pageID)).count == 2

        if pageViews.count != pages.count {
          pageViews.forEach { view in
            view.prepareForDismantle()
            view.removeFromSuperview()
          }
          pageViews = pages.map { _ in NativePageItem() }
          pageViews.forEach {
            stack.addArrangedSubview($0)
          }
        }

        for (index, data) in pages.enumerated() {
          let image = parent.viewModel.preloadedImage(for: data.pageID)
          let targetHeight = targetHeight(for: data, image: image)
          pageViews[index].update(
            with: data,
            viewModel: parent.viewModel,
            image: image,
            showPageNumber: parent.renderConfig.showPageNumber,
            showPageShadow: parent.renderConfig.showPageShadow,
            enableLiveText: parent.renderConfig.enableLiveText,
            enableImageContextMenu: parent.renderConfig.enableImageContextMenu,
            supportsPageSoloActions: parent.renderConfig.supportsPageSoloActions,
            canSoloPageFromCurrentPresentation: canSoloPageFromCurrentPresentation,
            background: parent.renderConfig.readerBackground,
            readingDirection: parent.readingDirection,
            displayMode: parent.displayMode,
            targetHeight: targetHeight
          )
        }

        contentStack?.semanticContentAttribute = parent.readingDirection == .rtl ? .forceRightToLeft : .forceLeftToRight
      }

      func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return contentStack
      }

      func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !isUpdatingFromSwiftUI else { return }

        let zoomed = scrollView.zoomScale > (parent.minScale + 0.01)
        if zoomed != parent.viewModel.isZoomed {
          DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.parent.viewModel.isZoomed != zoomed {
              self.parent.viewModel.isZoomed = zoomed
            }
          }
        }
      }

      func applyInitialZoomIfNeeded(in scrollView: UIScrollView) {
        guard let initialZoomID = parent.initialZoomID else { return }
        guard initialZoomID != lastInitialZoomID else { return }
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }

        scrollView.layoutIfNeeded()
        let contentSize = scrollView.contentSize
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        let scale = clampedScale(parent.initialZoomScale ?? parent.minScale)
        let baseAnchor = clampedAnchor(parent.initialZoomAnchor ?? CGPoint(x: 0.5, y: 0.5))
        let adjustedAnchor = clampedAnchor(adjustedAnchorForFillWidth(baseAnchor, contentSize: contentSize))
        let center = CGPoint(
          x: contentSize.width * adjustedAnchor.x,
          y: contentSize.height * adjustedAnchor.y
        )
        let zoomRect = calculateZoomRect(scale: scale, center: center, scrollView: scrollView)
        scrollView.zoom(to: zoomRect, animated: false)
        lastInitialZoomID = initialZoomID
      }

      func setupNativeInteractions(on scrollView: UIScrollView) {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        scrollView.addGestureRecognizer(doubleTap)
        doubleTapGesture = doubleTap
        applyDoubleTapGestureState()
      }

      func applyDoubleTapGestureState() {
        doubleTapGesture?.isEnabled = parent.renderConfig.doubleTapZoomMode.isEnabled
      }

      func applyDisplayModeIfNeeded(in scrollView: UIScrollView) {
        guard let stack = contentStack else { return }
        guard lastDisplayMode != parent.displayMode else { return }

        lastDisplayMode = parent.displayMode
        contentHeightConstraint?.isActive = false
        contentHeightConstraint = nil

        switch parent.displayMode {
        case .fit:
          stack.alignment = .fill
          stack.distribution = .fillEqually
          contentHeightConstraint = stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        case .fillWidth:
          stack.alignment = .top
          stack.distribution = .fill
          contentHeightConstraint = stack.heightAnchor.constraint(
            greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
          )
        }

        contentHeightConstraint?.isActive = true
      }

      private func targetHeight(for data: NativePageData, image: PlatformImage?) -> CGFloat {
        guard parent.displayMode == .fillWidth else { return parent.screenSize.height }
        let width = parent.screenSize.width
        guard width > 0 else { return parent.screenSize.height }

        if let image = image {
          let imageSize = data.rotation.rotatedSize(image.size)
          if imageSize.width > 0, imageSize.height > 0 {
            let height = width * imageSize.height / imageSize.width
            if height.isFinite && height > 0 {
              return height
            }
          }
        }

        if let page = parent.viewModel.readerPage(for: data.pageID)?.page,
          let pageWidth = page.width,
          let pageHeight = page.height,
          pageWidth > 0,
          pageHeight > 0
        {
          let sourceSize = data.rotation.rotatedSize(
            CGSize(width: CGFloat(pageWidth), height: CGFloat(pageHeight))
          )
          let height = width * sourceSize.height / sourceSize.width
          if height.isFinite && height > 0 {
            return height
          }
        }

        return parent.screenSize.height
      }

      @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let scrollView = gesture.view as? UIScrollView else { return }
        if scrollView.zoomScale > parent.minScale + 0.01 {
          scrollView.setZoomScale(parent.minScale, animated: true)
        } else {
          let point = gesture.location(in: contentStack)
          let zoomRect = calculateZoomRect(
            scale: CGFloat(parent.renderConfig.doubleTapZoomScale),
            center: point,
            scrollView: scrollView
          )
          scrollView.zoom(to: zoomRect, animated: true)
        }
      }

      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view, view is UIControl {
          return false
        }
        return true
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        return true
      }

      private func calculateZoomRect(scale: CGFloat, center: CGPoint, scrollView: UIScrollView) -> CGRect {
        let width = scrollView.frame.size.width / scale
        let height = scrollView.frame.size.height / scale
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
      }

      private func clampedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return parent.minScale }
        return min(max(scale, parent.minScale), parent.maxScale)
      }

      private func clampedAnchor(_ anchor: CGPoint) -> CGPoint {
        let x = min(max(anchor.x, 0), 1)
        let y = min(max(anchor.y, 0), 1)
        return CGPoint(x: x, y: y)
      }

      private func adjustedAnchorForFillWidth(_ anchor: CGPoint, contentSize: CGSize) -> CGPoint {
        guard parent.displayMode == .fillWidth else { return anchor }
        guard let data = parent.pages.first else { return anchor }
        let image = parent.viewModel.preloadedImage(for: data.pageID)
        let imageHeight = targetHeight(for: data, image: image)
        guard imageHeight > 0, contentSize.height > 0, imageHeight < contentSize.height else { return anchor }
        let adjustedY = anchor.y * (imageHeight / contentSize.height)
        return CGPoint(x: anchor.x, y: adjustedY)
      }
    }
  }

#endif
