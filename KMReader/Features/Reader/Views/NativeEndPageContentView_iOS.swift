#if os(iOS) || os(tvOS)
  import SwiftUI
  import UIKit

  @MainActor
  final class NativeEndPageContentView: UIView {
    private var previousBook: Book?
    private var nextBook: Book?
    private var nextBookOfflineState: NextBookOfflineState?
    private var remainingUnreadCount: Int?
    private var readListContext: ReaderReadListContext?
    private var readingDirection: ReadingDirection = .ltr
    private var sectionDisplayMode: NativeEndPagePresentation.SectionDisplayMode = .both
    private var renderConfig = ReaderRenderConfig(
      tapZoneMode: .defaultLayout,
      tapZoneInversionMode: .auto,
      showPageNumber: true,
      showPageShadow: true,
      readerBackground: .system,
      enableLiveText: false,
      enableImageContextMenu: false,
      supportsPageIsolationActions: false,
      doubleTapZoomScale: 3.0,
      doubleTapZoomMode: .enabled
    )
    private var onDismiss: (() -> Void)?
    private var lastIsPortrait: Bool?

    private let contentStack = UIStackView()
    private let sectionsStack = UIStackView()

    private let previousContainer = UIView()
    private let previousStack = UIStackView()
    private let previousBadgeLabel = UILabel()
    private let previousCoverView = NativeBookCoverView()
    private let previousMetadataStack = UIStackView()
    private let previousTitleLabel = UILabel()
    private let previousDetailLabel = UILabel()

    private let nextContainer = UIView()
    private let nextStack = UIStackView()
    private let nextBadgeLabel = UILabel()
    private let nextCoverView = NativeBookCoverView()
    private let nextMetadataStack = UIStackView()
    private let nextTitleLabel = UILabel()
    private let nextDetailLabel = UILabel()
    private let nextUnreadLabel = UILabel()
    private let nextDownloadStack = UIStackView()
    private let nextStatusContainer = UIView()
    private let nextProgressCircle = CircularProgressView()
    private let nextStatusIconView = UIImageView()
    private let caughtUpContainer = UIView()
    private let caughtUpColumn = UIStackView()
    private let caughtUpStack = UIStackView()
    private let caughtUpIconView = UIImageView()
    private let caughtUpLabel = UILabel()
    private let caughtUpUnreadLabel = UILabel()

    private let horizontalDividerStack = UIStackView()
    private let leadingDivider = UIView()
    private let dividerTitleLabel = UILabel()
    private let trailingDivider = UIView()
    private let verticalDivider = UIView()

    private let buttonContainer = UIView()
    private let closeButton = UIButton(type: .system)
    private var sectionsEqualWidthConstraint: NSLayoutConstraint?
    private var contentLeadingConstraint: NSLayoutConstraint?
    private var contentTrailingConstraint: NSLayoutConstraint?
    private var contentTopConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?
    private var contentMaxWidthConstraint: NSLayoutConstraint?
    private var previousMetadataWidthConstraint: NSLayoutConstraint?
    private var nextMetadataWidthConstraint: NSLayoutConstraint?
    private var horizontalDividerWidthConstraint: NSLayoutConstraint?
    private var previousCoverWidthConstraint: NSLayoutConstraint?
    private var previousCoverHeightConstraint: NSLayoutConstraint?
    private var nextCoverWidthConstraint: NSLayoutConstraint?
    private var nextCoverHeightConstraint: NSLayoutConstraint?
    private var verticalDividerHeightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
      super.init(frame: frame)
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      applyDynamicMetrics()
      applyLayoutModeIfNeeded()
    }

    func configure(
      previousBook: Book?,
      nextBook: Book?,
      readListContext: ReaderReadListContext?,
      readingDirection: ReadingDirection,
      sectionDisplayMode: NativeEndPagePresentation.SectionDisplayMode = .both,
      renderConfig: ReaderRenderConfig,
      nextBookOfflineState: NextBookOfflineState? = nil,
      remainingUnreadCount: Int? = nil,
      onDismiss: (() -> Void)?
    ) {
      self.previousBook = previousBook
      self.nextBook = nextBook
      self.nextBookOfflineState = nextBookOfflineState
      self.remainingUnreadCount = remainingUnreadCount
      self.readListContext = readListContext
      self.readingDirection = readingDirection
      self.sectionDisplayMode = sectionDisplayMode
      self.renderConfig = renderConfig
      self.onDismiss = onDismiss
      applyConfiguration()
      setNeedsLayout()
    }

    private func setupUI() {
      backgroundColor = UIColor(renderConfig.readerBackground.color)

      contentStack.translatesAutoresizingMaskIntoConstraints = false
      contentStack.axis = .vertical
      contentStack.alignment = .fill
      contentStack.spacing = 20
      contentStack.isLayoutMarginsRelativeArrangement = true
      contentStack.layoutMargins = UIEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
      addSubview(contentStack)

      sectionsStack.axis = .vertical
      sectionsStack.alignment = .fill
      sectionsStack.spacing = 20
      sectionsStack.isUserInteractionEnabled = false
      contentStack.addArrangedSubview(sectionsStack)

      previousContainer.translatesAutoresizingMaskIntoConstraints = false
      previousStack.translatesAutoresizingMaskIntoConstraints = false
      previousStack.axis = .vertical
      previousStack.alignment = .center
      previousStack.spacing = 6
      previousContainer.addSubview(previousStack)

      previousBadgeLabel.numberOfLines = 1
      previousBadgeLabel.textAlignment = .center
      previousBadgeLabel.adjustsFontForContentSizeCategory = true
      NativeEndPageLayoutMetrics.protectVerticalText(previousBadgeLabel)
      previousStack.addArrangedSubview(previousBadgeLabel)

      previousCoverView.translatesAutoresizingMaskIntoConstraints = false
      NativeEndPageLayoutMetrics.allowCoverToYieldVerticalSpace(previousCoverView)
      previousStack.addArrangedSubview(previousCoverView)

      previousMetadataStack.axis = .vertical
      previousMetadataStack.alignment = .fill
      previousMetadataStack.spacing = 4
      previousMetadataStack.setContentCompressionResistancePriority(.required, for: .vertical)
      previousStack.addArrangedSubview(previousMetadataStack)

      previousTitleLabel.numberOfLines = 2
      previousTitleLabel.textAlignment = .center
      previousTitleLabel.adjustsFontForContentSizeCategory = true
      previousTitleLabel.lineBreakMode = .byTruncatingTail
      NativeEndPageLayoutMetrics.protectVerticalText(previousTitleLabel)
      previousMetadataStack.addArrangedSubview(previousTitleLabel)

      previousDetailLabel.numberOfLines = 1
      previousDetailLabel.textAlignment = .center
      previousDetailLabel.adjustsFontForContentSizeCategory = true
      previousDetailLabel.lineBreakMode = .byTruncatingTail
      NativeEndPageLayoutMetrics.protectVerticalText(previousDetailLabel)
      previousMetadataStack.addArrangedSubview(previousDetailLabel)

      nextContainer.translatesAutoresizingMaskIntoConstraints = false
      nextStack.translatesAutoresizingMaskIntoConstraints = false
      nextStack.axis = .vertical
      nextStack.alignment = .center
      nextStack.spacing = 8
      nextContainer.addSubview(nextStack)

      nextBadgeLabel.numberOfLines = 1
      nextBadgeLabel.textAlignment = .center
      nextBadgeLabel.adjustsFontForContentSizeCategory = true
      NativeEndPageLayoutMetrics.protectVerticalText(nextBadgeLabel)
      nextStack.addArrangedSubview(nextBadgeLabel)

      nextCoverView.translatesAutoresizingMaskIntoConstraints = false
      NativeEndPageLayoutMetrics.allowCoverToYieldVerticalSpace(nextCoverView)
      nextStack.addArrangedSubview(nextCoverView)

      nextMetadataStack.axis = .vertical
      nextMetadataStack.alignment = .fill
      nextMetadataStack.spacing = 4
      nextMetadataStack.setContentCompressionResistancePriority(.required, for: .vertical)
      nextStack.addArrangedSubview(nextMetadataStack)

      nextTitleLabel.numberOfLines = 2
      nextTitleLabel.textAlignment = .center
      nextTitleLabel.adjustsFontForContentSizeCategory = true
      nextTitleLabel.lineBreakMode = .byTruncatingTail
      NativeEndPageLayoutMetrics.protectVerticalText(nextTitleLabel)
      nextMetadataStack.addArrangedSubview(nextTitleLabel)

      nextDetailLabel.numberOfLines = 1
      nextDetailLabel.textAlignment = .center
      nextDetailLabel.adjustsFontForContentSizeCategory = true
      nextDetailLabel.lineBreakMode = .byTruncatingTail
      NativeEndPageLayoutMetrics.protectVerticalText(nextDetailLabel)
      nextMetadataStack.addArrangedSubview(nextDetailLabel)

      nextUnreadLabel.numberOfLines = 1
      nextUnreadLabel.textAlignment = .center
      nextUnreadLabel.adjustsFontForContentSizeCategory = true
      nextUnreadLabel.lineBreakMode = .byTruncatingTail
      NativeEndPageLayoutMetrics.protectVerticalText(nextUnreadLabel)
      nextMetadataStack.addArrangedSubview(nextUnreadLabel)

      nextDownloadStack.axis = .vertical
      nextDownloadStack.alignment = .center
      nextDownloadStack.spacing = 6
      // Reserved slot (offline-first only): always occupies its space so
      // toggling the download state never re-lays out the end page content.
      nextDownloadStack.alpha = 0
      nextMetadataStack.addArrangedSubview(nextDownloadStack)

      // Fixed-height status slot: one centered icon per state — a circular
      // progress pie while downloading, a hollow iCloud when the next book
      // is not on device, and a checked iCloud once it is. Every state keeps
      // the exact same height so the end page layout never shifts.
      nextStatusContainer.translatesAutoresizingMaskIntoConstraints = false
      nextStatusContainer.heightAnchor.constraint(equalToConstant: 20).isActive = true
      nextStatusContainer.isAccessibilityElement = true
      nextDownloadStack.addArrangedSubview(nextStatusContainer)
      NSLayoutConstraint.activate([
        nextStatusContainer.leadingAnchor.constraint(equalTo: nextDownloadStack.leadingAnchor),
        nextStatusContainer.trailingAnchor.constraint(equalTo: nextDownloadStack.trailingAnchor),
      ])

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

      caughtUpStack.axis = .horizontal
      caughtUpStack.alignment = .center
      caughtUpStack.spacing = 8

      caughtUpIconView.image = UIImage(systemName: "checkmark.circle.fill")
      caughtUpIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
      caughtUpStack.addArrangedSubview(caughtUpIconView)

      caughtUpLabel.numberOfLines = 1
      caughtUpLabel.textAlignment = .center
      caughtUpLabel.adjustsFontForContentSizeCategory = true
      NativeEndPageLayoutMetrics.protectVerticalText(caughtUpLabel)
      caughtUpStack.addArrangedSubview(caughtUpLabel)

      caughtUpUnreadLabel.numberOfLines = 1
      caughtUpUnreadLabel.textAlignment = .center
      caughtUpUnreadLabel.adjustsFontForContentSizeCategory = true
      caughtUpUnreadLabel.lineBreakMode = .byTruncatingTail
      NativeEndPageLayoutMetrics.protectVerticalText(caughtUpUnreadLabel)

      caughtUpColumn.axis = .vertical
      caughtUpColumn.alignment = .center
      caughtUpColumn.spacing = 8
      caughtUpColumn.addArrangedSubview(caughtUpStack)
      caughtUpColumn.addArrangedSubview(caughtUpUnreadLabel)

      // The container fills the next-book column in every layout mode and
      // centers its content explicitly, so the caught-up block sits in the
      // middle of the side-by-side column instead of hugging its top edge.
      caughtUpColumn.translatesAutoresizingMaskIntoConstraints = false
      caughtUpContainer.addSubview(caughtUpColumn)
      NSLayoutConstraint.activate([
        caughtUpColumn.centerXAnchor.constraint(equalTo: caughtUpContainer.centerXAnchor),
        caughtUpColumn.centerYAnchor.constraint(equalTo: caughtUpContainer.centerYAnchor),
        caughtUpColumn.leadingAnchor.constraint(greaterThanOrEqualTo: caughtUpContainer.leadingAnchor),
        caughtUpColumn.trailingAnchor.constraint(lessThanOrEqualTo: caughtUpContainer.trailingAnchor),
        caughtUpColumn.topAnchor.constraint(greaterThanOrEqualTo: caughtUpContainer.topAnchor),
        caughtUpColumn.bottomAnchor.constraint(lessThanOrEqualTo: caughtUpContainer.bottomAnchor),
        // Keep the container at least as tall as its content: in stacked and
        // single-section modes it wraps the block, in side-by-side it fills.
        caughtUpContainer.heightAnchor.constraint(greaterThanOrEqualTo: caughtUpColumn.heightAnchor),
      ])
      nextStack.addArrangedSubview(caughtUpContainer)

      horizontalDividerStack.axis = .horizontal
      horizontalDividerStack.alignment = .center
      horizontalDividerStack.spacing = 10
      horizontalDividerStack.setContentCompressionResistancePriority(.required, for: .vertical)
      horizontalDividerStack.setContentHuggingPriority(.required, for: .vertical)
      horizontalDividerStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
      horizontalDividerWidthConstraint = horizontalDividerStack.widthAnchor.constraint(equalToConstant: 320)
      horizontalDividerWidthConstraint?.isActive = true

      leadingDivider.translatesAutoresizingMaskIntoConstraints = false
      leadingDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
      leadingDivider.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
      horizontalDividerStack.addArrangedSubview(leadingDivider)

      dividerTitleLabel.numberOfLines = 1
      dividerTitleLabel.textAlignment = .center
      dividerTitleLabel.adjustsFontForContentSizeCategory = true
      dividerTitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
      dividerTitleLabel.setContentHuggingPriority(.required, for: .vertical)
      horizontalDividerStack.addArrangedSubview(dividerTitleLabel)

      trailingDivider.translatesAutoresizingMaskIntoConstraints = false
      trailingDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
      trailingDivider.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
      horizontalDividerStack.addArrangedSubview(trailingDivider)
      leadingDivider.widthAnchor.constraint(equalTo: trailingDivider.widthAnchor).isActive = true

      verticalDivider.translatesAutoresizingMaskIntoConstraints = false
      verticalDivider.widthAnchor.constraint(equalToConstant: 1).isActive = true
      verticalDividerHeightConstraint = verticalDivider.heightAnchor.constraint(equalToConstant: 220)
      verticalDividerHeightConstraint?.isActive = true

      buttonContainer.translatesAutoresizingMaskIntoConstraints = false
      buttonContainer.setContentCompressionResistancePriority(.required, for: .vertical)
      contentStack.addArrangedSubview(buttonContainer)

      closeButton.translatesAutoresizingMaskIntoConstraints = false
      closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
      closeButton.setContentHuggingPriority(.required, for: .horizontal)
      closeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
      buttonContainer.addSubview(closeButton)

      let contentLeading = contentStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: leadingAnchor,
        constant: 40
      )
      let contentTrailing = contentStack.trailingAnchor.constraint(
        lessThanOrEqualTo: trailingAnchor,
        constant: -40
      )
      let contentTop = contentStack.topAnchor.constraint(
        greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor,
        constant: 40
      )
      let contentBottom = contentStack.bottomAnchor.constraint(
        lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor,
        constant: -40
      )
      let contentMaxWidth = contentStack.widthAnchor.constraint(
        lessThanOrEqualTo: widthAnchor,
        constant: -80
      )
      contentLeadingConstraint = contentLeading
      contentTrailingConstraint = contentTrailing
      contentTopConstraint = contentTop
      contentBottomConstraint = contentBottom
      contentMaxWidthConstraint = contentMaxWidth

      previousCoverWidthConstraint = previousCoverView.widthAnchor.constraint(equalToConstant: 120)
      previousCoverHeightConstraint = previousCoverView.heightAnchor.constraint(equalToConstant: 160)
      nextCoverWidthConstraint = nextCoverView.widthAnchor.constraint(equalToConstant: 120)
      nextCoverHeightConstraint = nextCoverView.heightAnchor.constraint(equalToConstant: 160)
      previousMetadataWidthConstraint = previousMetadataStack.widthAnchor.constraint(equalToConstant: 420)
      nextMetadataWidthConstraint = nextMetadataStack.widthAnchor.constraint(equalToConstant: 420)
      previousMetadataWidthConstraint?.priority = UILayoutPriority(999)
      nextMetadataWidthConstraint?.priority = UILayoutPriority(999)
      previousCoverHeightConstraint?.priority = NativeEndPageLayoutMetrics.coverHeightConstraintPriority
      nextCoverHeightConstraint?.priority = NativeEndPageLayoutMetrics.coverHeightConstraintPriority

      NSLayoutConstraint.activate([
        contentLeading,
        contentTrailing,
        contentTop,
        contentBottom,
        contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
        contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        contentMaxWidth,

        previousStack.leadingAnchor.constraint(equalTo: previousContainer.leadingAnchor),
        previousStack.trailingAnchor.constraint(equalTo: previousContainer.trailingAnchor),
        previousStack.topAnchor.constraint(equalTo: previousContainer.topAnchor),
        previousStack.bottomAnchor.constraint(equalTo: previousContainer.bottomAnchor),
        previousMetadataStack.widthAnchor.constraint(lessThanOrEqualTo: previousStack.widthAnchor),
        previousMetadataWidthConstraint!,

        nextStack.leadingAnchor.constraint(equalTo: nextContainer.leadingAnchor),
        nextStack.trailingAnchor.constraint(equalTo: nextContainer.trailingAnchor),
        nextStack.topAnchor.constraint(equalTo: nextContainer.topAnchor),
        nextStack.bottomAnchor.constraint(equalTo: nextContainer.bottomAnchor),
        nextMetadataStack.widthAnchor.constraint(lessThanOrEqualTo: nextStack.widthAnchor),
        nextMetadataWidthConstraint!,

        closeButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
        closeButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
        closeButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
        closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: buttonContainer.leadingAnchor),
        closeButton.trailingAnchor.constraint(lessThanOrEqualTo: buttonContainer.trailingAnchor),

        previousCoverWidthConstraint!,
        previousCoverHeightConstraint!,
        nextCoverWidthConstraint!,
        nextCoverHeightConstraint!,
      ])
    }

    private func applyConfiguration() {
      let textColor = contentColor
      let presentation = NativeEndPagePresentation.make(
        previousBook: previousBook,
        nextBook: nextBook,
        readListContext: readListContext,
        sectionDisplayMode: sectionDisplayMode,
        nextBookOfflineState: nextBookOfflineState,
        remainingUnreadCount: remainingUnreadCount
      )
      let relationTitle = presentation.relationTitle

      backgroundColor = UIColor(renderConfig.readerBackground.color)

      dividerTitleLabel.text = relationTitle
      dividerTitleLabel.isHidden = relationTitle.isEmpty

      let metrics = NativeEndPageLayoutMetrics.resolve(for: bounds)
      previousBadgeLabel.font = metrics.badgeFont
      previousTitleLabel.font = metrics.titleFont
      previousDetailLabel.font = metrics.detailFont
      nextBadgeLabel.font = metrics.badgeFont
      nextTitleLabel.font = metrics.titleFont
      nextDetailLabel.font = metrics.detailFont
      nextUnreadLabel.font = metrics.detailFont
      caughtUpLabel.font = .preferredFont(forTextStyle: .headline)
      caughtUpUnreadLabel.font = metrics.detailFont
      dividerTitleLabel.font = .preferredFont(forTextStyle: .caption1)

      previousBadgeLabel.textColor = textColor.withAlphaComponent(0.55)
      previousTitleLabel.textColor = textColor
      previousDetailLabel.textColor = textColor.withAlphaComponent(0.6)
      nextBadgeLabel.textColor = textColor.withAlphaComponent(0.55)
      nextTitleLabel.textColor = textColor
      nextDetailLabel.textColor = textColor.withAlphaComponent(0.6)
      nextUnreadLabel.textColor = textColor.withAlphaComponent(0.6)
      nextProgressCircle.color = textColor
      nextStatusIconView.tintColor = textColor.withAlphaComponent(0.6)
      caughtUpIconView.tintColor = textColor
      caughtUpLabel.textColor = textColor
      caughtUpUnreadLabel.textColor = textColor.withAlphaComponent(0.6)
      dividerTitleLabel.textColor = textColor.withAlphaComponent(0.8)
      leadingDivider.backgroundColor = textColor.withAlphaComponent(0.3)
      trailingDivider.backgroundColor = textColor.withAlphaComponent(0.3)
      verticalDivider.backgroundColor = textColor.withAlphaComponent(0.3)
      previousCoverView.useLightShadow = shouldUseLightCoverShadow
      nextCoverView.useLightShadow = shouldUseLightCoverShadow
      previousCoverView.imageBlendTintColor = coverBlendTintColor
      nextCoverView.imageBlendTintColor = coverBlendTintColor

      previousBadgeLabel.text = String(localized: "reader.previousBook").uppercased()
      nextBadgeLabel.text = presentation.next.badgeText

      if presentation.previous.isVisible {
        previousContainer.isHidden = false
        previousBadgeLabel.text = presentation.previous.badgeText
        previousCoverView.configure(bookID: presentation.previous.bookID)
        previousTitleLabel.text = presentation.previous.title
        previousDetailLabel.text = presentation.previous.detail
      } else {
        previousContainer.isHidden = true
        previousBadgeLabel.text = nil
        previousCoverView.configure(bookID: nil)
        previousTitleLabel.text = nil
        previousDetailLabel.text = nil
      }

      if presentation.next.isVisible {
        nextContainer.isHidden = false
        nextBadgeLabel.isHidden = presentation.next.badgeText == nil
        nextMetadataStack.isHidden = !presentation.next.showsMetadata
        caughtUpContainer.isHidden = !presentation.next.showsCaughtUp
        caughtUpLabel.text = presentation.next.showsCaughtUp ? String(localized: "You're all caught up!") : nil
        nextCoverView.isHidden = !presentation.next.showsCover
        nextCoverView.configure(bookID: presentation.next.bookID)
        nextTitleLabel.text = presentation.next.title
        nextDetailLabel.text = presentation.next.detail
        let unreadText = presentation.next.unreadRemainingText
        nextUnreadLabel.text = presentation.next.showsMetadata ? unreadText : nil
        nextUnreadLabel.isHidden = !presentation.next.showsMetadata || unreadText == nil
        caughtUpUnreadLabel.text = presentation.next.showsCaughtUp ? unreadText : nil
        caughtUpUnreadLabel.isHidden = !presentation.next.showsCaughtUp || unreadText == nil
        applyNextDownload(presentation.next.nextBookOfflineState)
      } else {
        nextContainer.isHidden = true
        nextBadgeLabel.isHidden = true
        nextMetadataStack.isHidden = true
        caughtUpContainer.isHidden = true
        caughtUpLabel.text = nil
        nextCoverView.isHidden = true
        nextCoverView.configure(bookID: nil)
        nextTitleLabel.text = nil
        nextDetailLabel.text = nil
        nextUnreadLabel.text = nil
        nextUnreadLabel.isHidden = true
        caughtUpUnreadLabel.text = nil
        caughtUpUnreadLabel.isHidden = true
        applyNextDownload(nil)
      }

      EndPageCloseButtonStyle.apply(to: closeButton, textColor: textColor)
      closeButton.isHidden = !presentation.showsCloseButton

      applyDynamicMetrics()
      applyLayoutModeIfNeeded(force: true)
    }

    private func applyLayoutModeIfNeeded(force: Bool = false) {
      guard bounds.width > 0, bounds.height > 0 else { return }
      let isPortrait = bounds.height >= bounds.width
      if !force, lastIsPortrait == isPortrait { return }
      lastIsPortrait = isPortrait

      let presentation = NativeEndPagePresentation.make(
        previousBook: previousBook,
        nextBook: nextBook,
        readListContext: readListContext,
        sectionDisplayMode: sectionDisplayMode
      )
      let showsRelationHeader = !isPortrait && !presentation.relationTitle.isEmpty

      previousStack.alignment = .center
      nextStack.alignment = .center
      previousTitleLabel.textAlignment = .center
      previousDetailLabel.textAlignment = .center
      nextTitleLabel.textAlignment = .center
      nextDetailLabel.textAlignment = .center
      caughtUpLabel.textAlignment = .center
      setArrangedSubviews(
        of: contentStack,
        with: [
          showsRelationHeader ? horizontalDividerStack : nil,
          sectionsStack,
          buttonContainer,
        ]
      )

      switch presentation.layoutMode(for: bounds.size, readingDirection: readingDirection) {
      case .singlePrevious:
        sectionsStack.axis = .vertical
        previousCoverView.isHidden = previousBook == nil
        setArrangedSubviews(
          of: sectionsStack,
          with: [
            previousContainer.isHidden ? nil : previousContainer
          ]
        )
      case .singleNext:
        sectionsStack.axis = .vertical
        previousCoverView.isHidden = previousBook == nil
        setArrangedSubviews(
          of: sectionsStack,
          with: [
            nextContainer.isHidden ? nil : nextContainer
          ]
        )
      case .stacked:
        sectionsStack.axis = .vertical
        previousCoverView.isHidden = true
        setArrangedSubviews(
          of: sectionsStack,
          with: [
            previousContainer.isHidden ? nil : previousContainer,
            horizontalDividerStack,
            nextContainer,
          ]
        )
      case .sideBySide(let nextOnLeadingSide, _):
        sectionsStack.axis = .horizontal
        previousCoverView.isHidden = previousBook == nil

        if nextOnLeadingSide {
          setArrangedSubviews(
            of: sectionsStack,
            with: [
              nextContainer,
              verticalDivider,
              previousContainer.isHidden ? nil : previousContainer,
            ]
          )
        } else {
          setArrangedSubviews(
            of: sectionsStack,
            with: [
              previousContainer.isHidden ? nil : previousContainer,
              verticalDivider,
              nextContainer,
            ]
          )
        }
      }

      updateSectionsEqualWidthConstraint()
    }

    private func setArrangedSubviews(of stack: UIStackView, with views: [UIView?]) {
      let filteredViews = views.compactMap { $0 }
      if stack.arrangedSubviews.elementsEqual(filteredViews, by: { $0 === $1 }) {
        return
      }

      sectionsEqualWidthConstraint?.isActive = false
      for subview in stack.arrangedSubviews {
        stack.removeArrangedSubview(subview)
        subview.removeFromSuperview()
      }

      for view in filteredViews {
        stack.addArrangedSubview(view)
      }
    }

    private func updateSectionsEqualWidthConstraint() {
      guard previousContainer.superview != nil, previousContainer.superview === nextContainer.superview else {
        sectionsEqualWidthConstraint?.isActive = false
        return
      }

      if sectionsEqualWidthConstraint == nil {
        sectionsEqualWidthConstraint = previousContainer.widthAnchor.constraint(equalTo: nextContainer.widthAnchor)
        sectionsEqualWidthConstraint?.priority = .defaultHigh
      }
      sectionsEqualWidthConstraint?.isActive = true
    }

    private func applyDynamicMetrics() {
      guard bounds.width > 0, bounds.height > 0 else { return }

      let isPortrait = bounds.height >= bounds.width
      let metrics = NativeEndPageLayoutMetrics.resolve(for: bounds)

      contentStack.spacing = metrics.stackSpacing
      sectionsStack.spacing = isPortrait ? metrics.portraitSectionSpacing : metrics.stackSpacing
      contentStack.layoutMargins = UIEdgeInsets(
        top: metrics.innerPadding,
        left: metrics.innerPadding,
        bottom: metrics.innerPadding,
        right: metrics.innerPadding
      )

      contentLeadingConstraint?.constant = metrics.outerPadding
      contentTrailingConstraint?.constant = -metrics.outerPadding
      contentTopConstraint?.constant = metrics.outerPadding
      contentBottomConstraint?.constant = -metrics.outerPadding
      contentMaxWidthConstraint?.constant = -metrics.outerPadding * 2
      previousMetadataWidthConstraint?.constant = metrics.sectionContentMaxWidth
      nextMetadataWidthConstraint?.constant = metrics.sectionContentMaxWidth
      horizontalDividerWidthConstraint?.constant = metrics.horizontalDividerWidth
      previousCoverWidthConstraint?.constant = metrics.coverWidth
      previousCoverHeightConstraint?.constant = metrics.coverHeight
      nextCoverWidthConstraint?.constant = metrics.coverWidth
      nextCoverHeightConstraint?.constant = metrics.coverHeight
      verticalDividerHeightConstraint?.constant = metrics.dividerHeight
    }

    private var contentColor: UIColor {
      switch renderConfig.readerBackground {
      case .black, .gray:
        return .white
      case .white:
        return .black
      case .sepia:
        return UIColor(renderConfig.readerBackground.contentColor)
      case .system:
        return .label
      }
    }

    private var shouldUseLightCoverShadow: Bool {
      switch renderConfig.readerBackground {
      case .black, .gray:
        return true
      case .white, .sepia:
        return false
      case .system:
        return traitCollection.userInterfaceStyle == .dark
      }
    }

    private var coverBlendTintColor: UIColor? {
      renderConfig.readerBackground.appliesImageMultiplyBlend
        ? UIColor(renderConfig.readerBackground.color)
        : nil
    }

    @objc private func handleClose() {
      onDismiss?()
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
      // the exact same height in every state, or the end page layout shifts.
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
        nextStatusIconView.image = UIImage(systemName: AppIcon.downloaded)
        nextStatusContainer.accessibilityLabel = String(localized: "Ready for offline reading")
      case nil:
        nextProgressCircle.alpha = 0
        nextStatusIconView.alpha = 1
        nextStatusIconView.image = UIImage(systemName: AppIcon.downloadPartial)
        nextStatusContainer.accessibilityLabel = String(localized: "status.not_downloaded")
      }
    }
  }
#endif
