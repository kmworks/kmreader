#if os(macOS)
  import AppKit

  @MainActor
  final class NativeBookCoverView: NSView {
    private let coverContainerView = NSView()
    private let coverImageView = NativeBookCoverImageView()
    private let sepiaOverlayView = NSView()

    private var coverImageTask: Task<Void, Never>?
    private var coverImageBookID: String?
    private var failedCoverImageBookID: String?
    private var sourceCoverImage: NSImage?

    var useLightShadow: Bool = false {
      didSet {
        updateShadowAppearance()
      }
    }

    var imageBlendTintColor: NSColor? {
      didSet {
        updateRenderedCoverImage()
      }
    }

    var cornerRadius: CGFloat = 12 {
      didSet {
        updateCoverImageDecoration()
      }
    }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    deinit {
      coverImageTask?.cancel()
    }

    func configure(bookID: String?) {
      updateCoverImage(for: bookID)
    }

    private func setupUI() {
      wantsLayer = true
      layer?.backgroundColor = NSColor.clear.cgColor

      coverContainerView.translatesAutoresizingMaskIntoConstraints = false
      coverContainerView.wantsLayer = true
      coverContainerView.layer?.backgroundColor = NSColor.clear.cgColor
      coverContainerView.layer?.shadowOpacity = 0
      coverContainerView.layer?.shadowOffset = CGSize(width: 0, height: -6)
      coverContainerView.layer?.shadowRadius = 16
      addSubview(coverContainerView)

      coverImageView.translatesAutoresizingMaskIntoConstraints = false
      coverImageView.imageScaling = .scaleProportionallyUpOrDown
      coverImageView.wantsLayer = true
      coverImageView.layer?.masksToBounds = true
      coverImageView.onDidLayout = { [weak self] in
        self?.updateCoverImageDecoration()
      }
      coverContainerView.addSubview(coverImageView)

      sepiaOverlayView.translatesAutoresizingMaskIntoConstraints = false
      sepiaOverlayView.wantsLayer = true
      sepiaOverlayView.isHidden = true
      coverImageView.addSubview(sepiaOverlayView)

      NSLayoutConstraint.activate([
        coverContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
        coverContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        coverContainerView.topAnchor.constraint(equalTo: topAnchor),
        coverContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        coverImageView.leadingAnchor.constraint(equalTo: coverContainerView.leadingAnchor),
        coverImageView.trailingAnchor.constraint(equalTo: coverContainerView.trailingAnchor),
        coverImageView.topAnchor.constraint(equalTo: coverContainerView.topAnchor),
        coverImageView.bottomAnchor.constraint(equalTo: coverContainerView.bottomAnchor),
        sepiaOverlayView.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor),
        sepiaOverlayView.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor),
        sepiaOverlayView.topAnchor.constraint(equalTo: coverImageView.topAnchor),
        sepiaOverlayView.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor),
      ])

      updateShadowAppearance()
    }

    private func updateCoverImage(for bookID: String?) {
      if coverImageBookID == bookID {
        if coverImageTask != nil || coverImageView.image != nil || failedCoverImageBookID == bookID {
          return
        }
      }

      if coverImageBookID != bookID {
        failedCoverImageBookID = nil
      }

      coverImageTask?.cancel()
      coverImageTask = nil
      coverImageBookID = bookID

      guard let bookID else {
        sourceCoverImage = nil
        coverImageView.image = nil
        coverImageView.layer?.mask = nil
        coverImageView.layer?.cornerRadius = cornerRadius
        coverImageView.layer?.backgroundColor = NSColor.clear.cgColor
        sepiaOverlayView.isHidden = true
        sepiaOverlayView.layer?.compositingFilter = nil
        sepiaOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
        coverContainerView.layer?.shadowOpacity = 0
        coverContainerView.layer?.shadowPath = nil
        failedCoverImageBookID = nil
        coverImageView.needsLayout = true
        return
      }

      sourceCoverImage = nil
      coverImageView.image = nil
      coverImageView.layer?.cornerRadius = 0
      coverImageView.layer?.backgroundColor = NSColor.clear.cgColor
      sepiaOverlayView.isHidden = true
      sepiaOverlayView.layer?.compositingFilter = nil
      sepiaOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
      coverContainerView.layer?.shadowOpacity = 0
      coverContainerView.layer?.shadowPath = nil

      coverImageTask = Task { @MainActor [weak self] in
        let image = await ThumbnailCache.shared.image(id: bookID, type: .book)
        guard !Task.isCancelled, let self else { return }
        guard self.coverImageBookID == bookID else { return }
        self.coverImageTask = nil
        self.sourceCoverImage = image
        self.failedCoverImageBookID = image == nil ? bookID : nil
        self.coverImageView.layer?.backgroundColor =
          image == nil ? self.coverPlaceholderColor.cgColor : NSColor.clear.cgColor
        self.updateRenderedCoverImage()
      }
    }

    private func updateRenderedCoverImage() {
      coverImageView.image = sourceCoverImage
      updateSepiaOverlay()
      coverImageView.needsLayout = true
    }

    private func updateCoverImageDecoration() {
      guard !coverImageView.bounds.isEmpty else { return }

      guard let image = coverImageView.image else {
        coverImageView.layer?.mask = nil
        coverImageView.layer?.cornerRadius = cornerRadius
        coverContainerView.layer?.shadowOpacity = 0
        coverContainerView.layer?.shadowPath = nil
        return
      }

      let contentRect = imageContentRect(for: image, in: coverImageView)
      let maskPath = CGPath(
        roundedRect: contentRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
      )
      let maskLayer = CAShapeLayer()
      maskLayer.path = maskPath
      coverImageView.layer?.mask = maskLayer
      coverImageView.layer?.cornerRadius = 0
      coverContainerView.layer?.shadowOpacity = 0.22
      coverContainerView.layer?.shadowPath = maskPath
    }

    private func updateSepiaOverlay() {
      guard sourceCoverImage != nil, let tintColor = imageBlendTintColor else {
        sepiaOverlayView.isHidden = true
        sepiaOverlayView.layer?.compositingFilter = nil
        sepiaOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
        return
      }
      sepiaOverlayView.isHidden = false
      sepiaOverlayView.layer?.backgroundColor = tintColor.cgColor
      sepiaOverlayView.layer?.compositingFilter = "multiplyBlendMode"
    }

    private func imageContentRect(for image: NSImage, in imageView: NSImageView) -> CGRect {
      let imageSize = image.size
      let viewSize = imageView.bounds.size
      guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
        return imageView.bounds
      }

      let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
      let width = imageSize.width * scale
      let height = imageSize.height * scale
      let x = (viewSize.width - width) / 2
      let y = (viewSize.height - height) / 2
      return CGRect(x: x, y: y, width: width, height: height)
    }

    private func updateShadowAppearance() {
      coverContainerView.layer?.shadowColor = effectiveShadowColor.cgColor
    }

    private var effectiveShadowColor: NSColor {
      if useLightShadow {
        return NSColor.white.withAlphaComponent(0.4)
      }
      return NSColor.black.withAlphaComponent(0.35)
    }

    private var coverPlaceholderColor: NSColor {
      NSColor.quaternaryLabelColor
    }
  }
#endif
