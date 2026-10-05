#if os(macOS)
  import AppKit
  import SwiftUI
  import VisionKit

  final class NativePageItem: NSView {
    private let imageView = NSImageView()
    private let sepiaOverlayView = NSView()
    private let animatedInlineContainer = NSView()
    private let animatedImageController = AnimatedImagePlayerController()
    private let preparedImageCache = PreparedReaderPageImageCache()
    private let pageNumberContainer = NSView()
    private let pageNumberLabel = NSTextField()
    private let progressIndicator = NSProgressIndicator()
    private let errorLabel = NSTextField()
    private let errorDetailLabel = NSTextField()
    private let retryButton = NSButton()
    private var retryToErrorConstraint: NSLayoutConstraint?
    private var retryToDetailConstraint: NSLayoutConstraint?

    private let overlayView = ImageAnalysisOverlayView()
    private var analysisTask: Task<Void, Never>?
    private var analyzedImage: NSImage?
    private var analysisRequestID: UInt64 = 0
    private var currentData: NativePageData?
    private var readingDirection: ReadingDirection = .ltr
    private var displayMode: PageDisplayMode = .fit
    private var readerBackground: ReaderBackground = .system
    private var showPageShadow = true
    private var enableLiveText = false
    private var enableImageContextMenu = false
    private var supportsPageIsolationActions = false
    private var canIsolatePageFromCurrentPresentation = false
    private weak var readerViewModel: ReaderViewModel?
    private let logger = AppLogger(.reader)
    private var analysisSourceImage: NSImage?
    private var heightConstraint: NSLayoutConstraint?

    init() {
      super.init(frame: .zero)
      setup()
    }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      setup()
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      setup()
    }

    deinit {
      analysisTask?.cancel()
    }

    func prepareForDismantle() {
      clearAnalysis()
      updateContextMenu(menu: nil)
      updateAnimatedPlayback(sourceFileURL: nil)
      imageView.isHidden = false
      imageView.image = nil
      preparedImageCache.clear()
      animatedInlineContainer.layer?.contents = nil
      analyzedImage = nil
      analysisSourceImage = nil
      updateSepiaOverlay()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil {
        prepareForDismantle()
      } else {
        if imageView.image == nil, let data = currentData {
          let pageSourceImage = preparedImage(
            from: readerViewModel?.preloadedImage(for: data.pageID),
            splitMode: data.splitMode,
            rotation: data.rotation
          )
          analysisSourceImage = pageSourceImage
          imageView.image = pageSourceImage
        }
        updateAnimatedPlayback(sourceFileURL: currentData?.animatedSourceFileURL)
        if enableLiveText {
          if let image = analysisSourceImage {
            analyzeImage(image)
          }
        }
        updateContextMenu()
      }
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
      super.mouseDown(with: event)
      restoreKeyboardFocus()
    }

    override func mouseUp(with event: NSEvent) {
      super.mouseUp(with: event)
      restoreKeyboardFocus()
    }

    private func restoreKeyboardFocus() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        if let window = self?.window {
          let keyboardHandler = window.contentView?.findViewOfType(KeyboardHandlerView.self)
          if let target = keyboardHandler, window.firstResponder !== target {
            window.makeFirstResponder(target)
          }
        }
      }
    }

    private func setup() {
      self.wantsLayer = true
      self.translatesAutoresizingMaskIntoConstraints = false

      imageView.imageScaling = .scaleProportionallyUpOrDown
      imageView.translatesAutoresizingMaskIntoConstraints = true
      imageView.wantsLayer = true

      imageView.layer?.shadowColor = NSColor.black.cgColor
      imageView.layer?.shadowOpacity = 0.25
      imageView.layer?.shadowOffset = CGSize(width: 0, height: -2)
      imageView.layer?.shadowRadius = 2

      addSubview(imageView)
      sepiaOverlayView.wantsLayer = true
      sepiaOverlayView.isHidden = true
      sepiaOverlayView.translatesAutoresizingMaskIntoConstraints = true
      addSubview(sepiaOverlayView)

      animatedInlineContainer.wantsLayer = true
      animatedInlineContainer.isHidden = true
      animatedInlineContainer.translatesAutoresizingMaskIntoConstraints = true
      animatedInlineContainer.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
      animatedInlineContainer.layer?.contentsGravity = .resizeAspect
      addSubview(animatedInlineContainer)

      overlayView.isHidden = true
      overlayView.wantsLayer = true
      overlayView.translatesAutoresizingMaskIntoConstraints = true
      addSubview(overlayView)
      overlayView.trackingImageView = imageView

      progressIndicator.style = .spinning
      progressIndicator.controlSize = .small
      progressIndicator.isDisplayedWhenStopped = false
      progressIndicator.translatesAutoresizingMaskIntoConstraints = false
      addSubview(progressIndicator)

      pageNumberContainer.wantsLayer = true
      pageNumberContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
      pageNumberContainer.layer?.cornerRadius = 6
      pageNumberContainer.translatesAutoresizingMaskIntoConstraints = false
      addSubview(pageNumberContainer)

      pageNumberLabel.isEditable = false
      pageNumberLabel.isSelectable = false
      pageNumberLabel.isBordered = false
      pageNumberLabel.drawsBackground = false
      pageNumberLabel.font = .systemFont(ofSize: PlatformHelper.pageNumberFontSize, weight: .semibold)
      pageNumberLabel.textColor = .white
      pageNumberLabel.alignment = .center
      pageNumberLabel.translatesAutoresizingMaskIntoConstraints = false
      pageNumberContainer.addSubview(pageNumberLabel)

      errorLabel.isEditable = false
      errorLabel.isSelectable = false
      errorLabel.isBordered = false
      errorLabel.drawsBackground = false
      errorLabel.font = .systemFont(ofSize: 14)
      errorLabel.textColor = .systemRed
      errorLabel.alignment = .center
      errorLabel.maximumNumberOfLines = 0
      errorLabel.lineBreakMode = .byWordWrapping
      errorLabel.isHidden = true
      errorLabel.translatesAutoresizingMaskIntoConstraints = false
      addSubview(errorLabel)

      errorDetailLabel.isEditable = false
      errorDetailLabel.isSelectable = false
      errorDetailLabel.isBordered = false
      errorDetailLabel.drawsBackground = false
      errorDetailLabel.font = .systemFont(ofSize: 12)
      errorDetailLabel.textColor = .secondaryLabelColor
      errorDetailLabel.alignment = .center
      errorDetailLabel.maximumNumberOfLines = 0
      errorDetailLabel.lineBreakMode = .byWordWrapping
      errorDetailLabel.isHidden = true
      errorDetailLabel.translatesAutoresizingMaskIntoConstraints = false
      addSubview(errorDetailLabel)

      retryButton.title = String(localized: "Retry")
      retryButton.bezelStyle = .rounded
      retryButton.target = self
      retryButton.action = #selector(handleRetryButtonClicked)
      retryButton.isHidden = true
      retryButton.translatesAutoresizingMaskIntoConstraints = false
      addSubview(retryButton)

      retryToErrorConstraint = retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12)
      retryToDetailConstraint = retryButton.topAnchor.constraint(
        equalTo: errorDetailLabel.bottomAnchor, constant: 12)
      retryToErrorConstraint?.isActive = true

      NSLayoutConstraint.activate([
        progressIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
        progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        pageNumberContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
        pageNumberContainer.heightAnchor.constraint(equalToConstant: 24),
        pageNumberLabel.centerXAnchor.constraint(equalTo: pageNumberContainer.centerXAnchor),
        pageNumberLabel.centerYAnchor.constraint(equalTo: pageNumberContainer.centerYAnchor),
        pageNumberLabel.leadingAnchor.constraint(equalTo: pageNumberContainer.leadingAnchor, constant: 4),
        pageNumberLabel.trailingAnchor.constraint(equalTo: pageNumberContainer.trailingAnchor, constant: -4),
        errorLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        errorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
        errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        errorDetailLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        errorDetailLabel.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 4),
        errorDetailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
        errorDetailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        retryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
      ])
    }

    @objc private func handleRetryButtonClicked() {
      guard let pageID = currentData?.pageID else { return }
      readerViewModel?.retryImageLoad(for: pageID)
    }

    func update(
      with data: NativePageData,
      viewModel: ReaderViewModel,
      image: PlatformImage?,
      showPageNumber: Bool,
      showPageShadow: Bool,
      enableLiveText: Bool,
      enableImageContextMenu: Bool,
      supportsPageIsolationActions: Bool,
      canIsolatePageFromCurrentPresentation: Bool,
      background: ReaderBackground,
      readingDirection: ReadingDirection,
      displayMode: PageDisplayMode,
      targetHeight: CGFloat
    ) {
      self.currentData = data
      self.readerViewModel = viewModel
      self.readingDirection = readingDirection
      self.displayMode = displayMode
      self.readerBackground = background
      self.showPageShadow = showPageShadow
      let shouldEnableLiveText = enableLiveText && !viewModel.isAnimatedPage(for: data.pageID)
      self.enableLiveText = shouldEnableLiveText
      self.enableImageContextMenu = enableImageContextMenu
      self.supportsPageIsolationActions = supportsPageIsolationActions
      self.canIsolatePageFromCurrentPresentation = canIsolatePageFromCurrentPresentation

      let pageSourceImage = preparedImage(
        from: image,
        splitMode: data.splitMode,
        rotation: data.rotation
      )

      let hasDisplayableImage = pageSourceImage != nil
      analysisSourceImage = shouldEnableLiveText ? pageSourceImage : nil
      imageView.image = pageSourceImage

      updateHeightConstraint(targetHeight)
      updateAnimatedPlayback(sourceFileURL: data.animatedSourceFileURL)

      if hasDisplayableImage, showPageNumber {
        if let displayedPageNumber = viewModel.displayPageNumber(for: data.pageID) {
          pageNumberLabel.stringValue = "\(displayedPageNumber)"
          pageNumberContainer.isHidden = false
        } else {
          pageNumberContainer.isHidden = true
        }
      } else {
        pageNumberContainer.isHidden = true
      }

      if let failure = data.failure {
        progressIndicator.stopAnimation(nil)
        errorLabel.stringValue = failure.title
        errorLabel.isHidden = false
        errorDetailLabel.stringValue = failure.detail ?? ""
        errorDetailLabel.isHidden = failure.detail == nil
        retryToDetailConstraint?.isActive = failure.detail != nil
        retryToErrorConstraint?.isActive = failure.detail == nil
        retryButton.isHidden = false
      } else if hasDisplayableImage {
        errorLabel.isHidden = true
        errorDetailLabel.isHidden = true
        retryButton.isHidden = true
        progressIndicator.stopAnimation(nil)
      } else if data.isLoading {
        errorLabel.isHidden = true
        errorDetailLabel.isHidden = true
        retryButton.isHidden = true
        progressIndicator.startAnimation(nil)
      } else {
        errorLabel.isHidden = true
        errorDetailLabel.isHidden = true
        retryButton.isHidden = true
        progressIndicator.stopAnimation(nil)
      }

      if shouldEnableLiveText, let img = pageSourceImage, !visibleRect.isEmpty {
        analyzeImage(img)
      } else if !shouldEnableLiveText {
        clearAnalysis()
      }

      updateShadowAppearance()
      updateContextMenu()
      updateOverlaysPosition()
    }

    private func updateShadowAppearance() {
      let shadowOpacity: Float = showPageShadow && imageView.image != nil ? 0.25 : 0
      imageView.layer?.shadowOpacity = shadowOpacity
      if shadowOpacity == 0 {
        imageView.layer?.shadowPath = nil
      }
    }

    private func preparedImage(from image: NSImage?, splitMode: PageSplitMode, rotation: ReaderRotation) -> NSImage? {
      guard let image else { return nil }
      let borderCropMode = AppConfig.divinaPageBorderCropMode
      return preparedImageCache.resolve(
        sourceImage: image,
        rotation: rotation,
        splitMode: splitMode,
        borderCropMode: borderCropMode
      ) {
        let rotatedImage = image.rotated(for: rotation)
        let splitImage =
          splitMode == .none ? rotatedImage : cropImageForSplitMode(image: rotatedImage, splitMode: splitMode)
        return cropBordersIfNeeded(splitImage, mode: borderCropMode)
      }
    }

    private func cropBordersIfNeeded(_ image: NSImage?, mode: ReaderPageBorderCropMode) -> NSImage? {
      guard let image else { return nil }
      guard mode != .disabled,
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
        let cropped = ReaderPageBorderCropper.crop(cgImage, mode: mode)
      else {
        return image
      }
      return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    private func cropImageForSplitMode(image: NSImage, splitMode: PageSplitMode) -> NSImage? {
      guard splitMode != .none else { return image }
      guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return image
      }

      let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

      let cropRect: CGRect
      if splitMode == .leftHalf {
        cropRect = CGRect(x: 0, y: 0, width: imageSize.width / 2, height: imageSize.height)
      } else {
        cropRect = CGRect(x: imageSize.width / 2, y: 0, width: imageSize.width / 2, height: imageSize.height)
      }

      guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
        return image
      }

      return NSImage(cgImage: croppedCGImage, size: NSSize(width: cropRect.width, height: cropRect.height))
    }

    private func updateSepiaOverlay() {
      guard !isAnimatedPlaybackVisible, readerBackground.appliesImageMultiplyBlend, imageView.image != nil else {
        sepiaOverlayView.isHidden = true
        sepiaOverlayView.layer?.compositingFilter = nil
        sepiaOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
        return
      }
      sepiaOverlayView.isHidden = false
      sepiaOverlayView.layer?.backgroundColor = NSColor(readerBackground.color).cgColor
      sepiaOverlayView.layer?.compositingFilter = "multiplyBlendMode"
    }

    func updateAnimatedPlayback(sourceFileURL: URL?) {
      layoutSubtreeIfNeeded()
      if let sourceFileURL {
        animatedInlineContainer.isHidden = false
        updateAnimatedPresentationState()
        animatedImageController.start(
          sourceFileURL: sourceFileURL,
          targetView: animatedInlineContainer
        )
      } else {
        animatedImageController.stop()
        animatedInlineContainer.layer?.contents = nil
        animatedInlineContainer.isHidden = true
        updateAnimatedPresentationState()
      }
    }

    private var isAnimatedPlaybackVisible: Bool {
      currentData?.animatedSourceFileURL != nil && !animatedInlineContainer.isHidden
    }

    private func updateAnimatedPresentationState() {
      imageView.isHidden = false
      updateShadowAppearance()
      updateSepiaOverlay()
    }

    private func updateHeightConstraint(_ targetHeight: CGFloat) {
      if displayMode == .fillWidth {
        if heightConstraint == nil {
          heightConstraint = heightAnchor.constraint(equalToConstant: targetHeight)
          heightConstraint?.priority = .required
          heightConstraint?.isActive = true
        } else {
          heightConstraint?.constant = targetHeight
        }
      } else {
        heightConstraint?.isActive = false
        heightConstraint = nil
      }
    }

    private func analyzeImage(_ image: NSImage) {
      if image === analyzedImage && (overlayView.analysis != nil || analysisTask != nil) {
        let requestID = analysisRequestID
        DispatchQueue.main.async { [weak self] in
          guard let self = self, self.analysisRequestID == requestID else { return }
          self.overlayView.isHidden = false
        }
        return
      }

      let pageNum = currentData?.pageID.pageNumber ?? -1
      let bookId = currentData?.pageID.bookId ?? "unknown"
      let startTime = Date()
      let requestID = nextAnalysisRequestID()

      analyzedImage = image
      analysisTask?.cancel()
      analysisTask = Task { [weak self] in
        let configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode])
        do {
          let analysis = try await LiveTextManager.shared.analyzer.analyze(
            image, orientation: .up, configuration: configuration)
          if Task.isCancelled { return }
          DispatchQueue.main.async { [weak self] in
            guard let self = self, self.analysisRequestID == requestID else { return }
            self.overlayView.analysis = analysis
            self.overlayView.preferredInteractionTypes = .automatic
            self.overlayView.isHidden = false
            self.analysisTask = nil
            let duration = Date().timeIntervalSince(startTime)
            self.logger.info(
              String(
                format: "[LiveText] [\(bookId)] ✅ Finished macOS analysis for page %d in %.2fs", pageNum + 1, duration))
          }
        } catch {
          if Task.isCancelled { return }
          DispatchQueue.main.async { [weak self] in
            guard let self = self, self.analysisRequestID == requestID else { return }
            self.analysisTask = nil
            self.logger.error("[LiveText] [\(bookId)] ❌ macOS Analysis failed for page \(pageNum + 1): \(error)")
          }
        }
      }
    }

    private func clearAnalysis() {
      let requestID = nextAnalysisRequestID()
      analysisTask?.cancel()
      analysisTask = nil
      analyzedImage = nil
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.analysisRequestID == requestID else { return }
        self.overlayView.analysis = nil
        self.overlayView.isHidden = true
      }
    }

    private func nextAnalysisRequestID() -> UInt64 {
      analysisRequestID &+= 1
      return analysisRequestID
    }

    private func updateOverlaysPosition() {
      guard let image = imageView.image else { return }
      let imageSize = image.size
      guard imageSize.width > 0, imageSize.height > 0 else { return }
      let viewSize = bounds.size
      if viewSize.width == 0 || viewSize.height == 0 { return }

      let widthRatio = viewSize.width / imageSize.width
      let heightRatio = viewSize.height / imageSize.height
      let scale: CGFloat
      if displayMode == .fillWidth {
        scale = widthRatio
      } else {
        scale = min(widthRatio, heightRatio)
      }

      let actualImageWidth = imageSize.width * scale
      let actualImageHeight = imageSize.height * scale
      let yOffset = (viewSize.height - actualImageHeight) / 2

      let isRTL = readingDirection == .rtl
      var xOffset: CGFloat = (viewSize.width - actualImageWidth) / 2

      if let alignment = currentData?.alignment {
        if alignment == .leading {
          xOffset = isRTL ? (viewSize.width - actualImageWidth) : 0
        } else if alignment == .trailing {
          xOffset = isRTL ? 0 : (viewSize.width - actualImageWidth)
        } else {
          xOffset = (viewSize.width - actualImageWidth) / 2
        }
      }

      let imgFrame = NSRect(x: xOffset, y: yOffset, width: actualImageWidth, height: actualImageHeight)
      imageView.frame = imgFrame
      sepiaOverlayView.frame = imgFrame
      animatedInlineContainer.frame = imgFrame
      overlayView.frame = imgFrame

      let topY = yOffset + actualImageHeight - 36

      if let alignment = currentData?.alignment {
        let isLeft: Bool
        if alignment == .center {
          isLeft = isRTL
        } else {
          if alignment == .trailing {
            isLeft = !isRTL
          } else {
            isLeft = isRTL
          }
        }

        if isLeft {
          pageNumberContainer.setFrameOrigin(NSPoint(x: xOffset + 12, y: topY))
        } else {
          pageNumberContainer.setFrameOrigin(
            NSPoint(x: xOffset + actualImageWidth - pageNumberContainer.bounds.width - 12, y: topY))
        }
      }
    }

    override func layout() {
      super.layout()
      updateOverlaysPosition()

      if showPageShadow, imageView.image != nil {
        let radius = imageView.layer?.shadowRadius ?? 0
        var shadowRect = imageView.bounds
        if let alignment = currentData?.alignment {
          if alignment == .trailing {
            shadowRect.size.width -= radius
          } else if alignment == .leading {
            shadowRect.origin.x += radius
            shadowRect.size.width -= radius
          }
        }
        imageView.layer?.shadowPath = CGPath(rect: shadowRect, transform: nil)
      } else {
        imageView.layer?.shadowPath = nil
      }

      if enableLiveText, currentData != nil,
        let image = analysisSourceImage,
        !visibleRect.isEmpty, overlayView.analysis == nil, analysisTask == nil
      {
        analyzeImage(image)
      }

      updateContextMenu()
    }

    private var contextMenuTargetViews: [NSView] {
      [
        imageView,
        sepiaOverlayView,
        animatedInlineContainer,
        overlayView,
        pageNumberContainer,
        pageNumberLabel,
      ]
    }

    private var shouldEnableContextMenu: Bool {
      enableImageContextMenu && imageView.image != nil
    }

    private func updateContextMenu() {
      let menu = shouldEnableContextMenu ? buildContextMenu() : nil
      updateContextMenu(menu: menu)
    }

    private func updateContextMenu(menu: NSMenu?) {
      for view in contextMenuTargetViews {
        view.menu = menu
      }
    }

    private func buildContextMenu() -> NSMenu? {
      guard let currentData, imageView.image != nil else { return nil }

      let menu = NSMenu()
      menu.addItem(makeShareMenuItem(for: currentData.pageID))

      if let isolationItem = makePageIsolationMenuItem(for: currentData.pageID) {
        menu.addItem(.separator())
        menu.addItem(isolationItem)
      }

      return menu.items.isEmpty ? nil : menu
    }

    private func makeShareMenuItem(for pageID: ReaderPageID) -> NSMenuItem {
      let item = NSMenuItem(
        title: String(localized: "Share"), action: #selector(handleShareContextMenuAction), keyEquivalent: "")
      item.target = self
      return item
    }

    private func makePageIsolationMenuItem(for pageID: ReaderPageID) -> NSMenuItem? {
      guard supportsPageIsolationActions, let readerViewModel else { return nil }
      guard readerViewModel.isPageEffectivelyPortrait(pageID) else { return nil }

      if readerViewModel.isPageIsolated(pageID) {
        let item = NSMenuItem(
          title: String(localized: "Cancel Isolation"),
          action: #selector(handleTogglePageIsolationContextMenuAction),
          keyEquivalent: ""
        )
        item.target = self
        return item
      }

      guard canIsolatePageFromCurrentPresentation else { return nil }
      let item = NSMenuItem(
        title: String(localized: "Isolate"),
        action: #selector(handleTogglePageIsolationContextMenuAction),
        keyEquivalent: ""
      )
      item.target = self
      return item
    }

    @objc private func handleShareContextMenuAction() {
      guard let pageID = currentData?.pageID else { return }
      // Share the original decoded page (no rotation/split/border crop); fall back
      // to the displayed image only if the preloaded original is unavailable.
      guard let image = readerViewModel?.preloadedImage(for: pageID) ?? imageView.image else { return }
      let fileName = readerViewModel?.page(for: pageID)?.fileName
      ImageShareHelper.share(image: image, fileName: fileName)
    }

    @objc private func handleTogglePageIsolationContextMenuAction() {
      guard let pageID = currentData?.pageID else { return }
      readerViewModel?.toggleIsolatePage(pageID)
      updateContextMenu()
    }

  }
#endif
