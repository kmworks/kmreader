//
// WebtoonFooterCell_iOS.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit

  class WebtoonFooterCell: UICollectionViewCell {
    var readerBackground: ReaderBackground = .system {
      didSet { applyBackground() }
    }

    private var previousBook: Book?
    private var nextBook: Book?
    private var nextBookOfflineState: NextBookOfflineState?
    private var remainingUnreadCount: Int?
    private var readListContext: ReaderReadListContext?
    private var onDismiss: (() -> Void)?

    private let topRegionView = UIView()
    private let bottomRegionView = UIView()
    private let previousBookStack = UIStackView()
    private let previousBadgeLabel = UILabel()
    private let previousTitleLabel = UILabel()
    private let previousDetailLabel = UILabel()

    private let dividerStack = UIStackView()
    private let leadingDivider = UIView()
    private let dividerTitleLabel = UILabel()
    private let trailingDivider = UIView()

    private let nextBookStack = UIStackView()
    private let nextBadgeLabel = UILabel()
    private let nextTitleLabel = UILabel()
    private let nextDetailLabel = UILabel()
    private let nextUnreadLabel = UILabel()
    private let nextDownloadStack = UIStackView()
    private let nextStatusContainer = UIView()
    private let nextProgressCircle = CircularProgressView()
    private let nextStatusIconView = UIImageView()
    private let caughtUpLabel = UILabel()
    private let caughtUpUnreadLabel = UILabel()
    private let caughtUpGroup = UIStackView()
    private let closeButton = UIButton(type: .system)

    override init(frame: CGRect) {
      super.init(frame: frame)
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func configure(
      previousBook: Book?,
      nextBook: Book?,
      readListContext: ReaderReadListContext?,
      nextBookOfflineState: NextBookOfflineState? = nil,
      remainingUnreadCount: Int? = nil,
      onDismiss: (() -> Void)?
    ) {
      self.previousBook = previousBook
      self.nextBook = nextBook
      self.nextBookOfflineState = nextBookOfflineState
      self.remainingUnreadCount = remainingUnreadCount
      self.readListContext = readListContext
      self.onDismiss = onDismiss
      applyContent()
    }

    private func setupUI() {
      topRegionView.translatesAutoresizingMaskIntoConstraints = false
      bottomRegionView.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(topRegionView)
      contentView.addSubview(bottomRegionView)

      previousBookStack.axis = .vertical
      previousBookStack.alignment = .center
      previousBookStack.spacing = 6
      previousBookStack.translatesAutoresizingMaskIntoConstraints = false
      previousBookStack.setContentHuggingPriority(.required, for: .vertical)
      previousBookStack.setContentCompressionResistancePriority(.required, for: .vertical)
      topRegionView.addSubview(previousBookStack)

      previousBadgeLabel.numberOfLines = 1
      previousBadgeLabel.textAlignment = .center
      previousBadgeLabel.adjustsFontForContentSizeCategory = true
      previousBadgeLabel.text = String(localized: "reader.previousBook").uppercased()
      previousBookStack.addArrangedSubview(previousBadgeLabel)

      previousTitleLabel.numberOfLines = 2
      previousTitleLabel.textAlignment = .center
      previousTitleLabel.adjustsFontForContentSizeCategory = true
      previousTitleLabel.lineBreakMode = .byTruncatingTail
      previousBookStack.addArrangedSubview(previousTitleLabel)

      previousDetailLabel.numberOfLines = 1
      previousDetailLabel.textAlignment = .center
      previousDetailLabel.adjustsFontForContentSizeCategory = true
      previousDetailLabel.lineBreakMode = .byTruncatingTail
      previousBookStack.addArrangedSubview(previousDetailLabel)

      dividerStack.axis = .horizontal
      dividerStack.alignment = .center
      dividerStack.spacing = 10
      dividerStack.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(dividerStack)

      leadingDivider.translatesAutoresizingMaskIntoConstraints = false
      leadingDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
      leadingDivider.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
      dividerStack.addArrangedSubview(leadingDivider)

      dividerTitleLabel.numberOfLines = 1
      dividerTitleLabel.textAlignment = .center
      dividerTitleLabel.adjustsFontForContentSizeCategory = true
      dividerStack.addArrangedSubview(dividerTitleLabel)

      trailingDivider.translatesAutoresizingMaskIntoConstraints = false
      trailingDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
      trailingDivider.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
      dividerStack.addArrangedSubview(trailingDivider)

      nextBookStack.axis = .vertical
      nextBookStack.alignment = .center
      nextBookStack.spacing = 6
      nextBookStack.translatesAutoresizingMaskIntoConstraints = false
      nextBookStack.setContentHuggingPriority(.required, for: .vertical)
      nextBookStack.setContentCompressionResistancePriority(.required, for: .vertical)
      bottomRegionView.addSubview(nextBookStack)

      nextBadgeLabel.numberOfLines = 1
      nextBadgeLabel.textAlignment = .center
      nextBadgeLabel.adjustsFontForContentSizeCategory = true
      nextBadgeLabel.text = String(localized: "reader.nextBook").uppercased()
      nextBookStack.addArrangedSubview(nextBadgeLabel)

      nextTitleLabel.numberOfLines = 2
      nextTitleLabel.textAlignment = .center
      nextTitleLabel.adjustsFontForContentSizeCategory = true
      nextTitleLabel.lineBreakMode = .byTruncatingTail
      nextBookStack.addArrangedSubview(nextTitleLabel)

      nextDetailLabel.numberOfLines = 1
      nextDetailLabel.textAlignment = .center
      nextDetailLabel.adjustsFontForContentSizeCategory = true
      nextDetailLabel.lineBreakMode = .byTruncatingTail
      nextBookStack.addArrangedSubview(nextDetailLabel)

      nextUnreadLabel.numberOfLines = 1
      nextUnreadLabel.textAlignment = .center
      nextUnreadLabel.adjustsFontForContentSizeCategory = true
      nextUnreadLabel.lineBreakMode = .byTruncatingTail
      nextBookStack.addArrangedSubview(nextUnreadLabel)

      nextDownloadStack.axis = .vertical
      nextDownloadStack.alignment = .center
      nextDownloadStack.spacing = 6
      // Reserved slot (offline-first only) inside the stack: the footer has a
      // fixed height, and the slot always occupies its space so the download
      // state never re-lays out (and visibly shifts) the next-book block.
      nextDownloadStack.alpha = 0
      nextBookStack.addArrangedSubview(nextDownloadStack)

      // Fixed-height status slot: one centered icon per state — a circular
      // progress pie while downloading, a hollow iCloud when the next book
      // is not on device, and a checked iCloud once it is. Every state keeps
      // the exact same height so the footer layout never shifts.
      nextStatusContainer.translatesAutoresizingMaskIntoConstraints = false
      nextStatusContainer.heightAnchor.constraint(equalToConstant: 20).isActive = true
      nextStatusContainer.isAccessibilityElement = true
      nextDownloadStack.addArrangedSubview(nextStatusContainer)

      nextProgressCircle.translatesAutoresizingMaskIntoConstraints = false
      nextStatusContainer.addSubview(nextProgressCircle)
      NSLayoutConstraint.activate([
        nextProgressCircle.centerXAnchor.constraint(equalTo: nextStatusContainer.centerXAnchor),
        nextProgressCircle.centerYAnchor.constraint(equalTo: nextStatusContainer.centerYAnchor),
        nextProgressCircle.widthAnchor.constraint(equalToConstant: 16),
        nextProgressCircle.heightAnchor.constraint(equalToConstant: 16),
      ])

      nextStatusIconView.translatesAutoresizingMaskIntoConstraints = false
      nextStatusIconView.contentMode = .scaleAspectFit
      nextStatusContainer.addSubview(nextStatusIconView)
      NSLayoutConstraint.activate([
        nextStatusIconView.centerXAnchor.constraint(equalTo: nextStatusContainer.centerXAnchor),
        nextStatusIconView.centerYAnchor.constraint(equalTo: nextStatusContainer.centerYAnchor),
        nextStatusIconView.widthAnchor.constraint(equalToConstant: 18),
        nextStatusIconView.heightAnchor.constraint(equalToConstant: 18),
      ])

      caughtUpLabel.numberOfLines = 0
      caughtUpLabel.textAlignment = .center
      caughtUpLabel.adjustsFontForContentSizeCategory = true

      caughtUpUnreadLabel.numberOfLines = 1
      caughtUpUnreadLabel.textAlignment = .center
      caughtUpUnreadLabel.adjustsFontForContentSizeCategory = true
      caughtUpUnreadLabel.lineBreakMode = .byTruncatingTail

      caughtUpGroup.axis = .vertical
      caughtUpGroup.alignment = .center
      caughtUpGroup.spacing = 6
      caughtUpGroup.addArrangedSubview(caughtUpLabel)
      caughtUpGroup.addArrangedSubview(caughtUpUnreadLabel)
      nextBookStack.addArrangedSubview(caughtUpGroup)
      nextBookStack.setCustomSpacing(20, after: caughtUpGroup)

      closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
      nextBookStack.addArrangedSubview(closeButton)

      NSLayoutConstraint.activate([
        dividerStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        dividerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 44),
        dividerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -44),

        topRegionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
        topRegionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 44),
        topRegionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -44),
        topRegionView.bottomAnchor.constraint(equalTo: dividerStack.topAnchor, constant: -12),

        bottomRegionView.topAnchor.constraint(equalTo: dividerStack.bottomAnchor, constant: 12),
        bottomRegionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 44),
        bottomRegionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -44),
        bottomRegionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),

        previousBookStack.centerXAnchor.constraint(equalTo: topRegionView.centerXAnchor),
        previousBookStack.centerYAnchor.constraint(equalTo: topRegionView.centerYAnchor),
        previousBookStack.leadingAnchor.constraint(
          greaterThanOrEqualTo: topRegionView.leadingAnchor),
        previousBookStack.trailingAnchor.constraint(
          lessThanOrEqualTo: topRegionView.trailingAnchor),

        nextBookStack.centerXAnchor.constraint(equalTo: bottomRegionView.centerXAnchor),
        nextBookStack.centerYAnchor.constraint(equalTo: bottomRegionView.centerYAnchor),
        nextBookStack.leadingAnchor.constraint(greaterThanOrEqualTo: bottomRegionView.leadingAnchor),
        nextBookStack.trailingAnchor.constraint(lessThanOrEqualTo: bottomRegionView.trailingAnchor),
        leadingDivider.widthAnchor.constraint(equalTo: trailingDivider.widthAnchor),
      ])

      applyBackground()
      applyContent()
    }

    private func applyBackground() {
      contentView.backgroundColor = UIColor(readerBackground.color)
      let textColor = UIColor(readerBackground.contentColor)
      previousBadgeLabel.font = preferredFont(textStyle: .caption1, weight: .semibold)
      previousTitleLabel.font = preferredFont(textStyle: .title3, design: .serif, weight: .bold)
      previousDetailLabel.font = .preferredFont(forTextStyle: .caption1)
      dividerTitleLabel.font = .preferredFont(forTextStyle: .caption1)
      nextBadgeLabel.font = preferredFont(textStyle: .caption1, weight: .semibold)
      nextTitleLabel.font = preferredFont(textStyle: .title3, design: .serif, weight: .bold)
      nextDetailLabel.font = .preferredFont(forTextStyle: .caption1)
      nextUnreadLabel.font = .preferredFont(forTextStyle: .caption1)
      caughtUpLabel.font = .preferredFont(forTextStyle: .headline)
      caughtUpUnreadLabel.font = .preferredFont(forTextStyle: .caption1)
      previousBadgeLabel.textColor = textColor.withAlphaComponent(0.55)
      previousTitleLabel.textColor = textColor
      previousDetailLabel.textColor = textColor.withAlphaComponent(0.6)
      dividerTitleLabel.textColor = textColor.withAlphaComponent(0.8)
      leadingDivider.backgroundColor = textColor.withAlphaComponent(0.3)
      trailingDivider.backgroundColor = textColor.withAlphaComponent(0.3)
      nextBadgeLabel.textColor = textColor.withAlphaComponent(0.55)
      nextTitleLabel.textColor = textColor
      nextDetailLabel.textColor = textColor.withAlphaComponent(0.6)
      nextUnreadLabel.textColor = textColor.withAlphaComponent(0.6)
      nextProgressCircle.color = textColor
      nextStatusIconView.tintColor = textColor.withAlphaComponent(0.6)
      caughtUpLabel.textColor = textColor
      caughtUpUnreadLabel.textColor = textColor.withAlphaComponent(0.6)
      EndPageCloseButtonStyle.apply(to: closeButton, textColor: textColor)
    }

    private func applyContent() {
      dividerTitleLabel.text = readListContext?.name ?? previousBook?.seriesTitle ?? nextBook?.seriesTitle

      if let previousBook {
        previousBookStack.isHidden = false
        previousTitleLabel.text = previousBook.readerChapterTitle
        previousDetailLabel.text = previousBook.readerChapterDetail
      } else {
        previousBookStack.isHidden = true
      }

      // A read list page reports list order, not series membership: the series
      // unread count would read as a list statistic there.
      let unreadText =
        readListContext == nil
        ? NativeEndPagePresentation.unreadRemainingText(for: remainingUnreadCount) : nil

      if let nextBook {
        closeButton.isHidden = true
        nextBadgeLabel.isHidden = false
        caughtUpGroup.isHidden = true
        caughtUpLabel.text = nil
        caughtUpUnreadLabel.text = nil
        nextTitleLabel.isHidden = false
        nextDetailLabel.isHidden = false
        nextTitleLabel.text = nextBook.readerChapterTitle
        nextDetailLabel.text = nextBook.readerChapterDetail
        nextUnreadLabel.text = unreadText
        nextUnreadLabel.isHidden = unreadText == nil
        applyNextDownload(nextBookOfflineState)
      } else {
        closeButton.isHidden = false
        nextBadgeLabel.isHidden = true
        nextTitleLabel.isHidden = true
        nextDetailLabel.isHidden = true
        nextTitleLabel.text = nil
        nextDetailLabel.text = nil
        nextUnreadLabel.text = nil
        nextUnreadLabel.isHidden = true
        // Caught up: no next book, so the download slot has nothing to show.
        nextDownloadStack.isHidden = true
        caughtUpGroup.isHidden = false
        caughtUpLabel.text = String(localized: "You're all caught up!")
        caughtUpUnreadLabel.text = unreadText
        caughtUpUnreadLabel.isHidden = unreadText == nil
      }

      EndPageCloseButtonStyle.apply(to: closeButton, textColor: UIColor(readerBackground.contentColor))
    }

    private func applyNextDownload(_ state: NextBookOfflineState?) {
      // Streaming readers never download ahead: collapse the slot entirely
      // instead of leaving a permanent empty band under the next book.
      nextDownloadStack.isHidden = !AppConfig.offlineFirstReading
      guard AppConfig.offlineFirstReading else {
        nextDownloadStack.alpha = 0
        return
      }
      nextDownloadStack.alpha = 1
      // Alpha, never isHidden below this point: the reserved slot must keep
      // the exact same height in every state, or the footer layout shifts.
      switch state {
      case .downloading(_, let progress)?:
        nextProgressCircle.alpha = 1
        nextStatusIconView.alpha = 0
        nextProgressCircle.progress = progress ?? 0
        let percent = (progress ?? 0).formatted(.percent.precision(.fractionLength(0)))
        nextStatusContainer.accessibilityLabel =
          String(localized: "Downloading next book…") + " \(percent)"
      case .ready?:
        nextProgressCircle.alpha = 0
        nextStatusIconView.alpha = 1
        nextStatusIconView.image = UIImage(systemName: "checkmark.icloud.fill")
        nextStatusContainer.accessibilityLabel = String(localized: "Ready for offline reading")
      case nil:
        nextProgressCircle.alpha = 0
        nextStatusIconView.alpha = 1
        nextStatusIconView.image = UIImage(systemName: "icloud")
        nextStatusContainer.accessibilityLabel = String(localized: "status.not_downloaded")
      }
    }

    @objc private func handleClose() {
      onDismiss?()
    }

    private func preferredFont(
      textStyle: UIFont.TextStyle,
      design: UIFontDescriptor.SystemDesign? = nil,
      weight: UIFont.Weight? = nil
    ) -> UIFont {
      var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
      if let design, let designedDescriptor = descriptor.withDesign(design) {
        descriptor = designedDescriptor
      }
      if let weight {
        descriptor = descriptor.addingAttributes([
          UIFontDescriptor.AttributeName.traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
      }
      return UIFont(descriptor: descriptor, size: 0)
    }
  }
#endif
