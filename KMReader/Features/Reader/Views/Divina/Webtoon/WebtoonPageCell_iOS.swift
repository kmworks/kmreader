//
// WebtoonPageCell_iOS.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit

  class WebtoonPageCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let sepiaOverlayView = UIView()
    private let mangaOverlayView = MangaOverlayView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let pageMarkerContainer = UIView()
    private let pageMarkerLabel = UILabel()
    private let errorLabel = UILabel()
    private let errorDetailLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var retryToErrorConstraint: NSLayoutConstraint?
    private var retryToDetailConstraint: NSLayoutConstraint?

    var onRetry: (() -> Void)?
    private var mangaTranslationResult: MangaPageTranslation?
    private var showsMangaTranslation = false

    var readerBackground: ReaderBackground = .system {
      didSet {
        applyBackground()
      }
    }

    var showPageNumber: Bool = true {
      didSet { pageMarkerLabel.isHidden = !showPageNumber }
    }

    override init(frame: CGRect) {
      super.init(frame: frame)
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
      applyBackground()
      imageView.contentMode = .scaleToFill
      imageView.clipsToBounds = true
      imageView.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(imageView)

      sepiaOverlayView.isUserInteractionEnabled = false
      sepiaOverlayView.isHidden = true
      sepiaOverlayView.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(sepiaOverlayView)

      mangaOverlayView.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(mangaOverlayView)

      pageMarkerLabel.font = .systemFont(ofSize: PlatformHelper.pageNumberFontSize, weight: .semibold)
      pageMarkerLabel.textColor = .white
      pageMarkerLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
      pageMarkerLabel.layer.cornerRadius = 6
      pageMarkerLabel.layer.masksToBounds = true
      pageMarkerLabel.textAlignment = .center
      pageMarkerLabel.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(pageMarkerLabel)

      loadingIndicator.color = .white
      loadingIndicator.hidesWhenStopped = true
      loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(loadingIndicator)

      errorLabel.font = .systemFont(ofSize: 32)
      errorLabel.textColor = .systemRed
      errorLabel.text = "⚠"
      errorLabel.textAlignment = .center
      errorLabel.isHidden = true
      errorLabel.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(errorLabel)

      retryButton.setTitle(String(localized: "Retry"), for: .normal)
      retryButton.isHidden = true
      retryButton.translatesAutoresizingMaskIntoConstraints = false
      retryButton.addTarget(self, action: #selector(handleRetryTapped), for: .touchUpInside)
      contentView.addSubview(retryButton)

      errorDetailLabel.font = .systemFont(ofSize: 13)
      errorDetailLabel.textColor = .secondaryLabel
      errorDetailLabel.numberOfLines = 0
      errorDetailLabel.textAlignment = .center
      errorDetailLabel.isHidden = true
      errorDetailLabel.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(errorDetailLabel)

      retryToErrorConstraint = retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12)
      retryToDetailConstraint = retryButton.topAnchor.constraint(
        equalTo: errorDetailLabel.bottomAnchor, constant: 12)
      retryToErrorConstraint?.isActive = true

      NSLayoutConstraint.activate([
        imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
        imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

        sepiaOverlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
        sepiaOverlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
        sepiaOverlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
        sepiaOverlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

        mangaOverlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
        mangaOverlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
        mangaOverlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
        mangaOverlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

        pageMarkerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
        pageMarkerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        pageMarkerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
        pageMarkerLabel.heightAnchor.constraint(equalToConstant: 24),

        loadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

        errorLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        errorLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

        errorDetailLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        errorDetailLabel.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 4),
        errorDetailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
        errorDetailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

        retryButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      ])
    }

    @objc private func handleRetryTapped() {
      errorLabel.isHidden = true
      errorDetailLabel.isHidden = true
      retryButton.isHidden = true
      loadingIndicator.isHidden = false
      loadingIndicator.startAnimating()
      onRetry?()
    }

    private func applyBackground() {
      contentView.backgroundColor = UIColor(readerBackground.color)
      imageView.backgroundColor = UIColor(readerBackground.color)
      updateSepiaOverlay()
      mangaOverlayView.update(
        result: mangaTranslationResult,
        visible: showsMangaTranslation,
        background: readerBackground,
        direction: AppConfig.mangaTranslation.textDirection,
        image: imageView.image
      )
    }

    private func updateSepiaOverlay() {
      guard readerBackground.appliesImageMultiplyBlend else {
        sepiaOverlayView.isHidden = true
        sepiaOverlayView.layer.compositingFilter = nil
        sepiaOverlayView.backgroundColor = .clear
        return
      }
      sepiaOverlayView.isHidden = false
      sepiaOverlayView.backgroundColor = UIColor(readerBackground.color)
      sepiaOverlayView.layer.compositingFilter = "multiplyBlendMode"
    }

    func updateMangaTranslation(result: MangaPageTranslation?, visible: Bool) {
      mangaTranslationResult = result
      showsMangaTranslation = visible
      mangaOverlayView.update(
        result: result,
        visible: visible,
        background: readerBackground,
        direction: AppConfig.mangaTranslation.textDirection,
        image: imageView.image
      )
    }

    func configure(
      pageLabel: String,
      image: UIImage?,
      showPageNumber: Bool
    ) {
      pageMarkerLabel.text = pageLabel
      pageMarkerLabel.isHidden = !showPageNumber

      if let image = image {
        // Instant display if image is provided
        setImage(image)
      } else {
        imageView.image = nil
        imageView.alpha = 0.0
        errorLabel.isHidden = true
        errorDetailLabel.isHidden = true
        retryButton.isHidden = true
        loadingIndicator.isHidden = false
        loadingIndicator.startAnimating()
      }
    }

    /// Set image directly from preloaded cache
    func setImage(_ image: UIImage) {
      loadingIndicator.stopAnimating()
      loadingIndicator.isHidden = true
      errorLabel.isHidden = true
      errorDetailLabel.isHidden = true
      retryButton.isHidden = true
      imageView.image = image
      imageView.alpha = 1.0
      updateMangaTranslation(result: mangaTranslationResult, visible: showsMangaTranslation)
    }

    func showError(failure: ReaderPageLoadFailure? = nil) {
      imageView.image = nil
      imageView.alpha = 0.0
      loadingIndicator.stopAnimating()
      errorLabel.isHidden = false
      errorDetailLabel.text = failure?.detail
      errorDetailLabel.isHidden = failure?.detail == nil
      retryToDetailConstraint?.isActive = failure?.detail != nil
      retryToErrorConstraint?.isActive = failure?.detail == nil
      retryButton.isHidden = false
    }

    override func prepareForReuse() {
      super.prepareForReuse()
      imageView.image = nil
      imageView.alpha = 0.0
      loadingIndicator.stopAnimating()
      loadingIndicator.isHidden = true
      errorLabel.isHidden = true
      errorDetailLabel.isHidden = true
      retryButton.isHidden = true
      onRetry = nil
      mangaTranslationResult = nil
      showsMangaTranslation = false
      mangaOverlayView.clear()
      pageMarkerLabel.isHidden = true
    }
  }
#endif
