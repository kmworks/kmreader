#if os(macOS)
  import AppKit
  import QuartzCore
  import SwiftUI

  // Extension to find KeyboardHandlerView in view hierarchy
  extension NSView {
    func findViewOfType<T: NSView>(_ type: T.Type) -> T? {
      if let view = self as? T {
        return view
      }
      for subview in subviews {
        if let found = subview.findViewOfType(type) {
          return found
        }
      }
      return nil
    }
  }

  struct PageScrollView: NSViewRepresentable {
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

    func makeNSView(context: Context) -> NSScrollView {
      let scrollView = FocusScrollView()
      scrollView.hasVerticalScroller = false
      scrollView.hasHorizontalScroller = false
      scrollView.allowsMagnification = true
      scrollView.minMagnification = minScale
      scrollView.maxMagnification = maxScale

      scrollView.backgroundColor = NSColor(renderConfig.readerBackground.color)
      scrollView.drawsBackground = true

      let contentStack = NSStackView()
      contentStack.orientation = .horizontal
      contentStack.distribution = .fillEqually
      contentStack.spacing = 0
      contentStack.translatesAutoresizingMaskIntoConstraints = false
      scrollView.documentView = contentStack
      context.coordinator.contentStack = contentStack

      NSLayoutConstraint.activate([
        contentStack.widthAnchor.constraint(equalToConstant: screenSize.width)
      ])

      context.coordinator.parent = self
      context.coordinator.scrollView = scrollView
      context.coordinator.applyDisplayModeIfNeeded(in: scrollView)
      context.coordinator.setupNativeInteractions(on: scrollView)
      context.coordinator.registerInvalidationObserver()

      return scrollView
    }

    @MainActor
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
      coordinator.prepareForDismantle()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
      context.coordinator.isUpdatingFromSwiftUI = true
      defer {
        DispatchQueue.main.async {
          context.coordinator.isUpdatingFromSwiftUI = false
          context.coordinator.applyInitialZoomIfNeeded(in: nsView)
        }
      }

      context.coordinator.parent = self
      context.coordinator.applyDisplayModeIfNeeded(in: nsView)
      context.coordinator.updatePages()

      // Force focus restoration on state changes to ensure keyboard responsiveness
      if let window = nsView.window {
        let keyboardHandler = window.contentView?.findViewOfType(KeyboardHandlerView.self)

        let isFirstResponderInvalid =
          window.firstResponder == nil
          || window.firstResponder is NSWindow
          || (keyboardHandler != nil && window.firstResponder !== keyboardHandler)

        if isFirstResponderInvalid, let target = keyboardHandler {
          DispatchQueue.main.async {
            if window.firstResponder !== target {
              window.makeFirstResponder(target)
            }
          }
        }
      }

      nsView.backgroundColor = NSColor(renderConfig.readerBackground.color)

      if context.coordinator.lastResetID != resetID {
        context.coordinator.lastResetID = resetID
        context.coordinator.lastInitialZoomID = nil
        nsView.magnification = minScale
      }

      // Sync constraints
      if let stack = context.coordinator.contentStack {
        for constraint in stack.constraints {
          if constraint.firstAttribute == .width { constraint.constant = screenSize.width }
          if constraint.firstAttribute == .height { constraint.constant = screenSize.height }
        }
      }
    }

    @MainActor
    class Coordinator: NSObject {
      var lastResetID: AnyHashable?
      var lastInitialZoomID: AnyHashable?
      var lastDisplayMode: PageDisplayMode?
      var isUpdatingFromSwiftUI = false

      var parent: PageScrollView!
      weak var scrollView: NSScrollView?

      weak var contentStack: NSStackView?
      var contentHeightConstraint: NSLayoutConstraint?
      private var pageViews: [NativePageItem] = []
      private var invalidationObserverToken: UUID?

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
        if let scrollView = scrollView {
          NotificationCenter.default.removeObserver(
            self, name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
          NotificationCenter.default.removeObserver(
            self, name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
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
          pageViews.forEach { stack.addArrangedSubview($0) }
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

        // Match reading direction
        contentStack?.userInterfaceLayoutDirection = parent.readingDirection == .rtl ? .rightToLeft : .leftToRight
      }

      func setupNativeInteractions(on scrollView: NSScrollView) {
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(handleScrollEnded(_:)),
          name: NSScrollView.didEndLiveScrollNotification,
          object: scrollView
        )
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(handleScrollEnded(_:)),
          name: NSScrollView.didEndLiveMagnifyNotification,
          object: scrollView
        )
      }

      func applyDisplayModeIfNeeded(in scrollView: NSScrollView) {
        guard let stack = contentStack else { return }
        guard lastDisplayMode != parent.displayMode else { return }

        lastDisplayMode = parent.displayMode
        contentHeightConstraint?.isActive = false

        switch parent.displayMode {
        case .fit:
          stack.alignment = .centerY
          stack.distribution = .fillEqually
          contentHeightConstraint = stack.heightAnchor.constraint(equalToConstant: parent.screenSize.height)
        case .fillWidth:
          stack.alignment = .top
          stack.distribution = .fill
          contentHeightConstraint = stack.heightAnchor.constraint(
            greaterThanOrEqualToConstant: parent.screenSize.height
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

      @objc func handleScrollEnded(_ notification: Notification) {
        guard !isUpdatingFromSwiftUI, let scrollView = scrollView else { return }

        // Handle Zoom state binding
        let zoomed = scrollView.magnification > (parent.minScale + 0.01)
        if zoomed != parent.viewModel.isZoomed {
          DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.parent.viewModel.isZoomed != zoomed {
              self.parent.viewModel.isZoomed = zoomed
            }
          }
        }

        // Paging Snap Logic
        if !zoomed {
          let pageWidth = parent.screenSize.width
          guard pageWidth > 0 else { return }

          let currentX = scrollView.contentView.bounds.origin.x
          let targetPage = round(currentX / pageWidth)
          let targetX = targetPage * pageWidth

          if abs(currentX - targetX) > 1 {
            NSAnimationContext.runAnimationGroup { context in
              context.duration = 0.2
              context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
              scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: targetX, y: 0))
              scrollView.reflectScrolledClipView(scrollView.contentView)
            }
          }
        }
      }

      func applyInitialZoomIfNeeded(in scrollView: NSScrollView) {
        guard let initialZoomID = parent.initialZoomID else { return }
        guard initialZoomID != lastInitialZoomID else { return }
        guard scrollView.contentView.bounds.width > 0, scrollView.contentView.bounds.height > 0 else {
          return
        }
        guard let documentView = scrollView.documentView else { return }
        documentView.layoutSubtreeIfNeeded()
        let baseSize = documentView.bounds.size
        guard baseSize.width > 0, baseSize.height > 0 else { return }

        let scale = clampedScale(parent.initialZoomScale ?? parent.minScale)
        let baseAnchor = clampedAnchor(parent.initialZoomAnchor ?? CGPoint(x: 0.5, y: 0.5))
        let adjustedAnchor = clampedAnchor(adjustedAnchorForFillWidth(baseAnchor, contentSize: baseSize))
        let convertedAnchorY = 1.0 - adjustedAnchor.y
        let center = CGPoint(
          x: baseSize.width * adjustedAnchor.x,
          y: baseSize.height * convertedAnchorY
        )
        let scaledCenter = CGPoint(x: center.x * scale, y: center.y * scale)
        let contentSize = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
        let viewport = scrollView.contentView.bounds.size

        var origin = CGPoint(x: scaledCenter.x - viewport.width / 2, y: scaledCenter.y - viewport.height / 2)
        let maxX = max(contentSize.width - viewport.width, 0)
        let maxY = max(contentSize.height - viewport.height, 0)
        origin.x = min(max(origin.x, 0), maxX)
        origin.y = min(max(origin.y, 0), maxY)

        scrollView.magnification = scale
        scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        let zoomed = scale > (parent.minScale + 0.01)
        if zoomed != parent.viewModel.isZoomed {
          parent.viewModel.isZoomed = zoomed
        }

        lastInitialZoomID = initialZoomID
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

  private class FocusScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
      self.nextResponder?.keyDown(with: event)
    }
  }

#endif
