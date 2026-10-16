#if os(iOS) || os(tvOS)
  import UIKit

  @MainActor
  final class NativeBookCoverView: UIView {
    private let coverContainerView = UIView()
    private let coverImageView = NativeBookCoverImageView()
    private let sepiaOverlayView = UIView()

    private var coverImageTask: Task<Void, Never>?
    private var coverImageBookID: String?
    private var failedCoverImageBookID: String?
    private var sourceCoverImage: UIImage?

    var useLightShadow: Bool = false {
      didSet {
        updateShadowAppearance()
      }
    }

    var imageBlendTintColor: UIColor? {
      didSet {
        updateRenderedCoverImage()
      }
    }

    var cornerRadius: CGFloat = 12 {
      didSet {
        updateCoverImageDecoration()
      }
    }

    override init(frame: CGRect) {
      super.init(frame: frame)
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
      backgroundColor = .clear

      coverContainerView.translatesAutoresizingMaskIntoConstraints = false
      coverContainerView.backgroundColor = .clear
      coverContainerView.layer.shadowOpacity = 0
      coverContainerView.layer.shadowOffset = CGSize(width: 0, height: 3)
      coverContainerView.layer.shadowRadius = 6
      addSubview(coverContainerView)

      coverImageView.translatesAutoresizingMaskIntoConstraints = false
      coverImageView.contentMode = .scaleAspectFit
      coverImageView.clipsToBounds = true
      coverImageView.layer.cornerRadius = 0
      coverImageView.onDidLayout = { [weak self] in
        self?.updateCoverImageDecoration()
      }
      coverContainerView.addSubview(coverImageView)

      sepiaOverlayView.translatesAutoresizingMaskIntoConstraints = false
      sepiaOverlayView.isHidden = true
      sepiaOverlayView.isUserInteractionEnabled = false
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
        coverImageView.layer.mask = nil
        coverImageView.layer.cornerRadius = cornerRadius
        coverImageView.backgroundColor = .clear
        sepiaOverlayView.isHidden = true
        sepiaOverlayView.layer.compositingFilter = nil
        sepiaOverlayView.backgroundColor = .clear
        coverContainerView.layer.shadowOpacity = 0
        coverContainerView.layer.shadowPath = nil
        failedCoverImageBookID = nil
        coverImageView.setNeedsLayout()
        return
      }

      sourceCoverImage = nil
      coverImageView.image = nil
      coverImageView.layer.cornerRadius = 0
      coverImageView.backgroundColor = .clear
      sepiaOverlayView.isHidden = true
      sepiaOverlayView.layer.compositingFilter = nil
      sepiaOverlayView.backgroundColor = .clear
      coverContainerView.layer.shadowOpacity = 0
      coverContainerView.layer.shadowPath = nil

      coverImageTask = Task { @MainActor [weak self] in
        let image = await ThumbnailCache.shared.image(id: bookID, type: .book)
        guard !Task.isCancelled, let self else { return }
        guard self.coverImageBookID == bookID else { return }
        self.coverImageTask = nil
        self.sourceCoverImage = image
        self.failedCoverImageBookID = image == nil ? bookID : nil
        self.coverImageView.backgroundColor = image == nil ? self.coverPlaceholderColor : .clear
        self.updateRenderedCoverImage()
      }
    }

    private func updateRenderedCoverImage() {
      coverImageView.image = sourceCoverImage
      updateSepiaOverlay()
      coverImageView.setNeedsLayout()
    }

    private func updateCoverImageDecoration() {
      guard !coverImageView.bounds.isEmpty else { return }

      guard let image = coverImageView.image else {
        coverImageView.layer.mask = nil
        coverImageView.layer.cornerRadius = cornerRadius
        coverContainerView.layer.shadowOpacity = 0
        coverContainerView.layer.shadowPath = nil
        return
      }

      let contentRect = imageContentRect(for: image, in: coverImageView)
      let maskPath = UIBezierPath(roundedRect: contentRect, cornerRadius: cornerRadius)
      let maskLayer = CAShapeLayer()
      maskLayer.path = maskPath.cgPath
      coverImageView.layer.mask = maskLayer
      coverImageView.layer.cornerRadius = 0
      coverContainerView.layer.shadowOpacity = 0.22
      coverContainerView.layer.shadowPath = maskPath.cgPath
    }

    private func updateSepiaOverlay() {
      guard sourceCoverImage != nil, let tintColor = imageBlendTintColor else {
        sepiaOverlayView.isHidden = true
        sepiaOverlayView.layer.compositingFilter = nil
        sepiaOverlayView.backgroundColor = .clear
        return
      }
      sepiaOverlayView.isHidden = false
      sepiaOverlayView.backgroundColor = tintColor
      sepiaOverlayView.layer.compositingFilter = "multiplyBlendMode"
    }

    private func imageContentRect(for image: UIImage, in imageView: UIImageView) -> CGRect {
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
      coverContainerView.layer.shadowColor = effectiveShadowColor.cgColor
    }

    private var effectiveShadowColor: UIColor {
      if useLightShadow {
        return UIColor.white.withAlphaComponent(0.4)
      }
      return UIColor.black.withAlphaComponent(0.35)
    }

    private var coverPlaceholderColor: UIColor {
      #if os(tvOS)
        return UIColor.white.withAlphaComponent(0.08)
      #else
        return .secondarySystemFill
      #endif
    }
  }
#endif
