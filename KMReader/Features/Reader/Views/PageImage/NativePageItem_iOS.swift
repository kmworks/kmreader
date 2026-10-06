#if os(iOS) || os(tvOS)
  import SwiftUI
  import UIKit

  #if os(iOS) || os(macOS)
    import VisionKit
  #endif

  final class NativePageItem: UIView {
    private let imageView = UIImageView()
    private let sepiaOverlayView = UIView()
    private let animatedInlineContainer = UIView()
    private let animatedImageController = AnimatedImagePlayerController()
    private let preparedImageCache = PreparedReaderPageImageCache()
    private let pageNumberLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private let errorDetailLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var retryToErrorConstraint: NSLayoutConstraint?
    private var retryToDetailConstraint: NSLayoutConstraint?
    private var currentData: NativePageData?
    private weak var viewModel: ReaderViewModel?
    private var readingDirection: ReadingDirection = .ltr
    private var displayMode: PageDisplayMode = .fit
    private var readerBackground: ReaderBackground = .system
    private var showPageShadow = true
    private var enableLiveText = false
    private var enableImageContextMenu = false
    private var supportsPageIsolationActions = false
    private var canIsolatePageFromCurrentPresentation = false
    private let logger = AppLogger(.reader)

    #if os(iOS) || os(macOS)
      private let interaction = ImageAnalysisInteraction()
      private var analysisTask: Task<Void, Never>?
      private var analyzedImage: UIImage?
      private var analysisSourceImage: UIImage?
      private var analysisRequestID: UInt64 = 0
    #endif

    #if os(iOS)
      private lazy var contextMenuInteraction = UIContextMenuInteraction(delegate: self)
    #endif

    private var heightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
      super.init(frame: frame)
      setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
      #if os(iOS) || os(macOS)
        analysisTask?.cancel()
      #endif
    }

    func prepareForDismantle() {
      #if os(iOS) || os(macOS)
        if imageView.interactions.contains(where: { $0 === interaction }) {
          imageView.removeInteraction(interaction)
        }
        clearAnalysis()
        analyzedImage = nil
        analysisSourceImage = nil
      #endif
      #if os(iOS)
        removeContextMenuInteractionIfNeeded()
      #endif
      updateAnimatedPlayback(sourceFileURL: nil)
      imageView.isHidden = false
      imageView.image = nil
      preparedImageCache.clear()
      animatedInlineContainer.layer.contents = nil
      updateSepiaOverlay()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      if window == nil {
        prepareForDismantle()
      } else {
        if imageView.image == nil, let data = currentData {
          let pageSourceImage = preparedImage(
            from: viewModel?.preloadedImage(for: data.pageID),
            splitMode: data.splitMode,
            rotation: data.rotation
          )
          #if os(iOS) || os(macOS)
            analysisSourceImage = pageSourceImage
          #endif
          imageView.image = pageSourceImage
        }
        updateAnimatedPlayback(sourceFileURL: currentData?.animatedSourceFileURL)
        #if os(iOS) || os(macOS)
          if enableLiveText {
            analyzeImage()
          }
        #endif
        #if os(iOS)
          updateContextMenuInteraction()
        #endif
      }
    }

    private func setup() {
      imageView.contentMode = .scaleAspectFit
      imageView.translatesAutoresizingMaskIntoConstraints = true
      imageView.isUserInteractionEnabled = true
      imageView.clipsToBounds = false

      imageView.layer.shadowColor = UIColor.black.cgColor
      imageView.layer.shadowOpacity = 0.25
      imageView.layer.shadowOffset = CGSize(width: 0, height: 2)
      imageView.layer.shadowRadius = 2
      imageView.layer.masksToBounds = false

      addSubview(imageView)
      sepiaOverlayView.isUserInteractionEnabled = false
      sepiaOverlayView.isHidden = true
      addSubview(sepiaOverlayView)

      animatedInlineContainer.isUserInteractionEnabled = false
      animatedInlineContainer.isHidden = true
      animatedInlineContainer.backgroundColor = .clear
      animatedInlineContainer.layer.contentsGravity = .resizeAspect
      addSubview(animatedInlineContainer)

      loadingIndicator.hidesWhenStopped = true
      loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
      addSubview(loadingIndicator)

      pageNumberLabel.font = .systemFont(ofSize: PlatformHelper.pageNumberFontSize, weight: .semibold)
      pageNumberLabel.textColor = .white
      pageNumberLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
      pageNumberLabel.layer.cornerRadius = 6
      pageNumberLabel.layer.masksToBounds = true
      pageNumberLabel.textAlignment = .center
      pageNumberLabel.translatesAutoresizingMaskIntoConstraints = false
      addSubview(pageNumberLabel)

      errorLabel.isHidden = true
      errorLabel.textColor = .systemRed
      errorLabel.numberOfLines = 0
      errorLabel.textAlignment = .center
      errorLabel.translatesAutoresizingMaskIntoConstraints = false
      addSubview(errorLabel)

      errorDetailLabel.isHidden = true
      errorDetailLabel.textColor = .secondaryLabel
      errorDetailLabel.font = .systemFont(ofSize: 13)
      errorDetailLabel.numberOfLines = 0
      errorDetailLabel.textAlignment = .center
      errorDetailLabel.translatesAutoresizingMaskIntoConstraints = false
      addSubview(errorDetailLabel)

      retryButton.isHidden = true
      retryButton.setTitle(String(localized: "Retry"), for: .normal)
      retryButton.translatesAutoresizingMaskIntoConstraints = false
      retryButton.addTarget(self, action: #selector(handleRetryButtonTapped), for: .touchUpInside)
      addSubview(retryButton)

      retryToErrorConstraint = retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12)
      retryToDetailConstraint = retryButton.topAnchor.constraint(
        equalTo: errorDetailLabel.bottomAnchor, constant: 12)
      retryToErrorConstraint?.isActive = true

      NSLayoutConstraint.activate([
        loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
        loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        pageNumberLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
        pageNumberLabel.heightAnchor.constraint(equalToConstant: 24),
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

    @objc private func handleRetryButtonTapped() {
      guard let pageID = currentData?.pageID else { return }
      viewModel?.retryImageLoad(for: pageID)
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
      self.viewModel = viewModel
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

      #if os(iOS) || os(macOS)
        analysisSourceImage = shouldEnableLiveText ? pageSourceImage : nil
      #endif

      let hasDisplayableImage = pageSourceImage != nil
      imageView.image = pageSourceImage

      updateHeightConstraint(targetHeight)
      updateAnimatedPlayback(sourceFileURL: data.animatedSourceFileURL)

      if hasDisplayableImage, showPageNumber {
        if let displayedPageNumber = viewModel.displayPageNumber(for: data.pageID) {
          pageNumberLabel.text = "\(displayedPageNumber)"
          pageNumberLabel.isHidden = false
        } else {
          pageNumberLabel.isHidden = true
        }
      } else {
        pageNumberLabel.isHidden = true
      }

      if let failure = data.failure {
        loadingIndicator.stopAnimating()
        errorLabel.text = failure.title
        errorLabel.isHidden = false
        errorDetailLabel.text = failure.detail
        errorDetailLabel.isHidden = failure.detail == nil
        retryToDetailConstraint?.isActive = failure.detail != nil
        retryToErrorConstraint?.isActive = failure.detail == nil
        retryButton.isHidden = false
      } else if hasDisplayableImage {
        errorLabel.isHidden = true
        errorDetailLabel.isHidden = true
        retryButton.isHidden = true
        loadingIndicator.stopAnimating()
      } else if data.isLoading {
        errorLabel.isHidden = true
        errorDetailLabel.isHidden = true
        retryButton.isHidden = true
        loadingIndicator.startAnimating()
      } else {
        errorLabel.isHidden = true
        errorDetailLabel.isHidden = true
        retryButton.isHidden = true
        loadingIndicator.stopAnimating()
      }

      #if os(iOS) || os(macOS)
        if shouldEnableLiveText {
          if window != nil && !isHidden {
            if !imageView.interactions.contains(where: { $0 === interaction }) {
              imageView.addInteraction(interaction)
            }
            analyzeImage()
          }
        } else {
          if imageView.interactions.contains(where: { $0 === interaction }) {
            imageView.removeInteraction(interaction)
          }
          clearAnalysis()
        }
      #endif

      #if os(iOS)
        updateContextMenuInteraction()
      #endif

      updateShadowAppearance()
      setNeedsLayout()
    }

    /// Size of the prepared image shown for `pageID` (rotated and cropped), or
    /// nil while it is not displayed.
    func displayedImageSize(for pageID: ReaderPageID) -> CGSize? {
      guard currentData?.pageID == pageID else { return nil }
      return imageView.image?.size
    }

    private func updateShadowAppearance() {
      let shadowOpacity: Float = showPageShadow && imageView.image != nil ? 0.25 : 0
      imageView.layer.shadowOpacity = shadowOpacity
      if shadowOpacity == 0 {
        imageView.layer.shadowPath = nil
      }
    }

    private func preparedImage(from image: UIImage?, splitMode: PageSplitMode, rotation: ReaderRotation) -> UIImage? {
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

    private func cropBordersIfNeeded(_ image: UIImage?, mode: ReaderPageBorderCropMode) -> UIImage? {
      guard let image else { return nil }
      guard mode != .disabled, let cgImage = image.cgImage else { return image }
      guard let cropped = ReaderPageBorderCropper.crop(cgImage, mode: mode) else { return image }
      return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private func cropImageForSplitMode(image: UIImage, splitMode: PageSplitMode) -> UIImage? {
      guard splitMode != .none else { return image }

      let imageSize = image.size
      let scale = image.scale

      let cropRect: CGRect
      if splitMode == .leftHalf {
        cropRect = CGRect(x: 0, y: 0, width: imageSize.width / 2, height: imageSize.height)
      } else {
        cropRect = CGRect(x: imageSize.width / 2, y: 0, width: imageSize.width / 2, height: imageSize.height)
      }

      guard
        let cgImage = image.cgImage?.cropping(
          to: CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.size.width * scale,
            height: cropRect.size.height * scale
          ))
      else {
        return image
      }

      return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
    }

    private func updateSepiaOverlay() {
      guard !isAnimatedPlaybackVisible, readerBackground.appliesImageMultiplyBlend, imageView.image != nil else {
        sepiaOverlayView.isHidden = true
        sepiaOverlayView.layer.compositingFilter = nil
        sepiaOverlayView.backgroundColor = .clear
        return
      }
      sepiaOverlayView.isHidden = false
      sepiaOverlayView.backgroundColor = UIColor(readerBackground.color)
      sepiaOverlayView.layer.compositingFilter = "multiplyBlendMode"
    }

    func updateAnimatedPlayback(sourceFileURL: URL?) {
      layoutIfNeeded()
      if let sourceFileURL {
        animatedInlineContainer.isHidden = false
        updateAnimatedPresentationState()
        animatedImageController.start(
          sourceFileURL: sourceFileURL,
          targetLayer: animatedInlineContainer.layer
        )
      } else {
        animatedImageController.stop()
        animatedInlineContainer.layer.contents = nil
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

    #if os(iOS) || os(macOS)
      private func analyzeImage() {
        guard let image = analysisSourceImage ?? imageView.image else { return }

        if image === analyzedImage && (interaction.analysis != nil || analysisTask != nil) {
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
            let analysis = try await LiveTextManager.shared.analyzer.analyze(image, configuration: configuration)
            if Task.isCancelled { return }
            await MainActor.run {
              guard let self = self, self.analysisRequestID == requestID else { return }
              self.interaction.analysis = analysis
              self.interaction.preferredInteractionTypes = .automatic
              self.analysisTask = nil
              let duration = Date().timeIntervalSince(startTime)
              self.logger.info(
                String(format: "[LiveText] [\(bookId)] ✅ Finished analysis for page %d in %.2fs", pageNum + 1, duration)
              )
            }
          } catch {
            if Task.isCancelled { return }
            await MainActor.run {
              guard let self = self, self.analysisRequestID == requestID else { return }
              self.analysisTask = nil
              self.logger.error("[LiveText] [\(bookId)] ❌ Analysis failed for page \(pageNum + 1): \(error)")
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
          self.interaction.analysis = nil
        }
      }

      private func nextAnalysisRequestID() -> UInt64 {
        analysisRequestID &+= 1
        return analysisRequestID
      }
    #endif

    override func layoutSubviews() {
      super.layoutSubviews()
      updateOverlaysPosition()

      if showPageShadow, imageView.image != nil {
        let radius = imageView.layer.shadowRadius
        var shadowRect = imageView.bounds
        if let alignment = currentData?.alignment {
          if alignment == .trailing {
            shadowRect.size.width -= radius
          } else if alignment == .leading {
            shadowRect.origin.x += radius
            shadowRect.size.width -= radius
          }
        }
        imageView.layer.shadowPath = UIBezierPath(rect: shadowRect).cgPath
      } else {
        imageView.layer.shadowPath = nil
      }

      #if os(iOS) || os(macOS)
        if enableLiveText, imageView.image != nil,
          window != nil, !isHidden, interaction.analysis == nil, analysisTask == nil
        {
          if !imageView.interactions.contains(where: { $0 === interaction }) {
            imageView.addInteraction(interaction)
          }
          analyzeImage()
        }
      #endif

      #if os(iOS)
        updateContextMenuInteraction()
      #endif
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

      imageView.frame = CGRect(x: xOffset, y: yOffset, width: actualImageWidth, height: actualImageHeight)
      sepiaOverlayView.frame = imageView.frame
      animatedInlineContainer.frame = imageView.frame

      let topY = yOffset
      let pageLabelWidth = max(30, pageNumberLabel.intrinsicContentSize.width + 16)
      let pageLabelHeight: CGFloat = 24

      let alignment = currentData?.alignment ?? .center
      let isLeft: Bool
      if alignment == .center {
        isLeft = isRTL
      } else if alignment == .trailing {
        isLeft = !isRTL
      } else {
        isLeft = isRTL
      }

      let topInset: CGFloat = 12
      if isLeft {
        pageNumberLabel.frame = CGRect(
          x: xOffset + 12, y: topY + topInset, width: pageLabelWidth, height: pageLabelHeight)
      } else {
        pageNumberLabel.frame = CGRect(
          x: xOffset + actualImageWidth - pageLabelWidth - 12,
          y: topY + topInset,
          width: pageLabelWidth,
          height: pageLabelHeight
        )
      }
    }

    func getCombinedRectRelativeToImage() -> CGRect {
      let imageRectInSelf = CGRect(origin: .zero, size: imageView.bounds.size)
      var combinedRect = imageRectInSelf

      if !pageNumberLabel.isHidden {
        let labelFrameInImage = convert(pageNumberLabel.frame, to: imageView)
        combinedRect = combinedRect.union(labelFrameInImage)
      }

      return combinedRect
    }

    #if os(iOS)
      private var shouldEnableContextMenuInteraction: Bool {
        enableImageContextMenu && !enableLiveText && imageView.image != nil
      }

      private func updateContextMenuInteraction() {
        guard shouldEnableContextMenuInteraction else {
          removeContextMenuInteractionIfNeeded()
          return
        }

        if !imageView.interactions.contains(where: { $0 === contextMenuInteraction }) {
          imageView.addInteraction(contextMenuInteraction)
        }
      }

      private func removeContextMenuInteractionIfNeeded() {
        if imageView.interactions.contains(where: { $0 === contextMenuInteraction }) {
          imageView.removeInteraction(contextMenuInteraction)
        }
      }

      private func makeContextMenu() -> UIMenu? {
        guard let currentData, imageView.image != nil else { return nil }

        var sections: [UIMenuElement] = [
          UIMenu(options: .displayInline, children: [makeShareAction(for: currentData.pageID)])
        ]
        if let isolateAction = makePageIsolationAction(for: currentData.pageID) {
          sections.append(UIMenu(options: .displayInline, children: [isolateAction]))
        }

        return UIMenu(children: sections)
      }

      private func makeShareAction(for pageID: ReaderPageID) -> UIAction {
        UIAction(title: String(localized: "Share"), image: UIImage(systemName: AppIcon.share)) {
          [weak self] _ in
          self?.shareCurrentImage(for: pageID)
        }
      }

      private func makePageIsolationAction(for pageID: ReaderPageID) -> UIAction? {
        guard supportsPageIsolationActions, let viewModel else { return nil }
        guard viewModel.isPageEffectivelyPortrait(pageID) else { return nil }

        if viewModel.isPageIsolated(pageID) {
          return UIAction(
            title: String(localized: "Cancel Isolation"),
            image: UIImage(systemName: "rectangle.portrait.slash")
          ) { [weak self] _ in
            self?.viewModel?.toggleIsolatePage(pageID)
          }
        }

        guard canIsolatePageFromCurrentPresentation else { return nil }
        return UIAction(
          title: String(localized: "Isolate"),
          image: UIImage(systemName: "rectangle.portrait")
        ) { [weak self] _ in
          self?.viewModel?.toggleIsolatePage(pageID)
        }
      }

      private func shareCurrentImage(for pageID: ReaderPageID) {
        // Share the original decoded page (no rotation/split/border crop); fall back
        // to the displayed image only if the preloaded original is unavailable.
        guard let image = viewModel?.preloadedImage(for: pageID) ?? imageView.image else { return }
        let fileName = viewModel?.page(for: pageID)?.fileName
        ImageShareHelper.share(image: image, fileName: fileName)
      }

      private func makePreview() -> UITargetedPreview? {
        guard !imageView.bounds.isEmpty else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(rect: imageView.bounds)
        return UITargetedPreview(view: imageView, parameters: parameters)
      }
    #endif
  }

  #if os(iOS)
    extension NativePageItem: UIContextMenuInteractionDelegate {
      func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
      ) -> UIContextMenuConfiguration? {
        guard imageView.bounds.contains(location) else { return nil }
        guard makeContextMenu() != nil else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
          self?.makeContextMenu()
        }
      }

      func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
      ) -> UITargetedPreview? {
        makePreview()
      }

      func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
      ) -> UITargetedPreview? {
        makePreview()
      }
    }
  #endif
#endif
