#if os(macOS)
  import AppKit
  import SwiftUI

  @MainActor
  final class NativeEndPageContentView: NSView {
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
      supportsPageSoloActions: false,
      doubleTapZoomScale: 3.0,
      doubleTapZoomMode: .enabled
    )
    private var onDismiss: (() -> Void)?
    private var lastIsPortrait: Bool?

    private let contentStack = NSStackView()
    private let sectionsStack = NSStackView()

    private let previousContainer = NSView()
    private let previousStack = NSStackView()
    private let previousBadgeLabel = NSTextField(labelWithString: "")
    private let previousCoverView = NativeBookCoverView()
    private let previousMetadataStack = NSStackView()
    private let previousTitleLabel = NSTextField(labelWithString: "")
    private let previousDetailLabel = NSTextField(labelWithString: "")

    private let nextContainer = NSView()
    private let nextStack = NSStackView()
    private let nextBadgeLabel = NSTextField(labelWithString: "")
    private let nextCoverView = NativeBookCoverView()
    private let nextMetadataStack = NSStackView()
    private let nextTitleLabel = NSTextField(labelWithString: "")
    private let nextDetailLabel = NSTextField(labelWithString: "")
    private let nextUnreadLabel = NSTextField(labelWithString: "")
    private let nextDownloadStack = NSStackView()
    private let nextStatusContainer = NSView()
    private let nextProgressCircle = CircularProgressView()
    private let nextStatusIconView = NSImageView()
    private let caughtUpContainer = NSView()
    private let caughtUpColumn = NSStackView()
    private let caughtUpStack = NSStackView()
    private let caughtUpIconView = NSImageView()
    private let caughtUpLabel = NSTextField(labelWithString: "")
    private let caughtUpUnreadLabel = NSTextField(labelWithString: "")

    private let horizontalDividerStack = NSStackView()
    private let leadingDivider = NSView()
    private let dividerTitleLabel = NSTextField(labelWithString: "")
    private let trailingDivider = NSView()
    private let verticalDivider = NSView()
    private let closeButton = NSButton()

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
    private var sectionsEqualWidthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      setupUI()
    }

    override func viewDidChangeEffectiveAppearance() {
      super.viewDidChangeEffectiveAppearance()
      applyAppearanceColors()
    }

    /// Dynamic colors (the `.system` reader background and `.primary` content
    /// color) must be snapshotted under this view's own appearance. `configure`
    /// can run before the view enters a window, where the current drawing
    /// appearance still reflects the system light mode, baking a white
    /// background that then clashes with the dark-mode text.
    private func applyAppearanceColors() {
      let backgroundColor = NSColor(renderConfig.readerBackground.color)
      let textColor = NSColor(renderConfig.readerBackground.contentColor)
      effectiveAppearance.performAsCurrentDrawingAppearance {
        layer?.backgroundColor = backgroundColor.cgColor
        leadingDivider.layer?.backgroundColor = textColor.withAlphaComponent(0.3).cgColor
        trailingDivider.layer?.backgroundColor = textColor.withAlphaComponent(0.3).cgColor
        verticalDivider.layer?.backgroundColor = textColor.withAlphaComponent(0.3).cgColor
      }
      previousCoverView.useLightShadow = shouldUseLightCoverShadow
      nextCoverView.useLightShadow = shouldUseLightCoverShadow
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
      super.layout()
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
      needsLayout = true
    }

    private func setupUI() {
      wantsLayer = true
      applyAppearanceColors()

      contentStack.translatesAutoresizingMaskIntoConstraints = false
      contentStack.orientation = .vertical
      contentStack.alignment = .centerX
      contentStack.spacing = 20
      addSubview(contentStack)

      sectionsStack.orientation = .vertical
      sectionsStack.alignment = .centerX
      sectionsStack.spacing = 20
      contentStack.addArrangedSubview(sectionsStack)

      previousContainer.translatesAutoresizingMaskIntoConstraints = false
      previousStack.translatesAutoresizingMaskIntoConstraints = false
      previousStack.orientation = .vertical
      previousStack.alignment = .centerX
      previousStack.spacing = 8
      previousContainer.addSubview(previousStack)

      previousBadgeLabel.alignment = .center
      previousBadgeLabel.maximumNumberOfLines = 1
      previousBadgeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      previousStack.addArrangedSubview(previousBadgeLabel)

      previousCoverView.translatesAutoresizingMaskIntoConstraints = false
      previousStack.addArrangedSubview(previousCoverView)

      previousMetadataStack.orientation = .vertical
      previousMetadataStack.alignment = .centerX
      previousMetadataStack.spacing = 4
      previousStack.addArrangedSubview(previousMetadataStack)

      previousTitleLabel.alignment = .center
      previousTitleLabel.maximumNumberOfLines = 2
      previousTitleLabel.lineBreakMode = .byTruncatingTail
      previousTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      previousMetadataStack.addArrangedSubview(previousTitleLabel)

      previousDetailLabel.alignment = .center
      previousDetailLabel.maximumNumberOfLines = 1
      previousDetailLabel.lineBreakMode = .byTruncatingTail
      previousDetailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      previousMetadataStack.addArrangedSubview(previousDetailLabel)

      nextContainer.translatesAutoresizingMaskIntoConstraints = false
      nextStack.translatesAutoresizingMaskIntoConstraints = false
      nextStack.orientation = .vertical
      nextStack.alignment = .centerX
      nextStack.spacing = 8
      nextContainer.addSubview(nextStack)

      nextBadgeLabel.alignment = .center
      nextBadgeLabel.maximumNumberOfLines = 1
      nextBadgeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      nextStack.addArrangedSubview(nextBadgeLabel)

      nextCoverView.translatesAutoresizingMaskIntoConstraints = false
      nextStack.addArrangedSubview(nextCoverView)

      nextMetadataStack.orientation = .vertical
      nextMetadataStack.alignment = .centerX
      nextMetadataStack.spacing = 4
      nextStack.addArrangedSubview(nextMetadataStack)

      nextTitleLabel.alignment = .center
      nextTitleLabel.maximumNumberOfLines = 2
      nextTitleLabel.lineBreakMode = .byTruncatingTail
      nextTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      nextMetadataStack.addArrangedSubview(nextTitleLabel)

      nextDetailLabel.alignment = .center
      nextDetailLabel.maximumNumberOfLines = 1
      nextDetailLabel.lineBreakMode = .byTruncatingTail
      nextDetailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      nextMetadataStack.addArrangedSubview(nextDetailLabel)

      nextUnreadLabel.alignment = .center
      nextUnreadLabel.maximumNumberOfLines = 1
      nextUnreadLabel.lineBreakMode = .byTruncatingTail
      nextUnreadLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      nextMetadataStack.addArrangedSubview(nextUnreadLabel)

      nextDownloadStack.orientation = .vertical
      nextDownloadStack.alignment = .centerX
      nextDownloadStack.spacing = 6
      // Reserved slot (offline-first only): always occupies its space so
      // toggling the download state never re-lays out the end page content.
      nextDownloadStack.alphaValue = 0
      nextDownloadStack.translatesAutoresizingMaskIntoConstraints = false
      nextMetadataStack.addArrangedSubview(nextDownloadStack)

      // Fixed-height status slot: one centered icon per state — a circular
      // progress pie while downloading, a hollow iCloud when the next book
      // is not on device, and a checked iCloud once it is. Every state keeps
      // the exact same height so the end page layout never shifts.
      nextStatusContainer.translatesAutoresizingMaskIntoConstraints = false
      nextStatusContainer.heightAnchor.constraint(equalToConstant: 20).isActive = true
      nextStatusContainer.setAccessibilityElement(true)
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
      nextStatusContainer.addSubview(nextStatusIconView)
      NSLayoutConstraint.activate([
        nextStatusIconView.centerXAnchor.constraint(equalTo: nextStatusContainer.centerXAnchor),
        nextStatusIconView.centerYAnchor.constraint(equalTo: nextStatusContainer.centerYAnchor),
        nextStatusIconView.widthAnchor.constraint(equalToConstant: 18),
        nextStatusIconView.heightAnchor.constraint(equalToConstant: 18),
      ])

      caughtUpStack.orientation = .horizontal
      caughtUpStack.alignment = .centerY
      caughtUpStack.spacing = 8

      caughtUpIconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
      caughtUpStack.addArrangedSubview(caughtUpIconView)

      caughtUpLabel.alignment = .center
      caughtUpLabel.maximumNumberOfLines = 2
      caughtUpLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      caughtUpStack.addArrangedSubview(caughtUpLabel)

      caughtUpUnreadLabel.alignment = .center
      caughtUpUnreadLabel.maximumNumberOfLines = 1
      caughtUpUnreadLabel.lineBreakMode = .byTruncatingTail
      caughtUpUnreadLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

      caughtUpColumn.orientation = .vertical
      caughtUpColumn.alignment = .centerX
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

      horizontalDividerStack.orientation = .horizontal
      horizontalDividerStack.alignment = .centerY
      horizontalDividerStack.spacing = 10
      horizontalDividerStack.setContentCompressionResistancePriority(.required, for: .vertical)
      horizontalDividerStack.setContentHuggingPriority(.required, for: .vertical)
      horizontalDividerStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
      horizontalDividerWidthConstraint = horizontalDividerStack.widthAnchor.constraint(equalToConstant: 320)
      horizontalDividerWidthConstraint?.isActive = true

      leadingDivider.wantsLayer = true
      leadingDivider.translatesAutoresizingMaskIntoConstraints = false
      leadingDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
      leadingDivider.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
      horizontalDividerStack.addArrangedSubview(leadingDivider)

      dividerTitleLabel.alignment = .center
      dividerTitleLabel.maximumNumberOfLines = 1
      dividerTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      dividerTitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
      dividerTitleLabel.setContentHuggingPriority(.required, for: .vertical)
      horizontalDividerStack.addArrangedSubview(dividerTitleLabel)

      trailingDivider.wantsLayer = true
      trailingDivider.translatesAutoresizingMaskIntoConstraints = false
      trailingDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
      trailingDivider.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
      horizontalDividerStack.addArrangedSubview(trailingDivider)
      leadingDivider.widthAnchor.constraint(equalTo: trailingDivider.widthAnchor).isActive = true

      verticalDivider.wantsLayer = true
      verticalDivider.translatesAutoresizingMaskIntoConstraints = false
      verticalDivider.widthAnchor.constraint(equalToConstant: 1).isActive = true
      verticalDividerHeightConstraint = verticalDivider.heightAnchor.constraint(equalToConstant: 220)
      verticalDividerHeightConstraint?.isActive = true

      closeButton.bezelStyle = .rounded
      closeButton.target = self
      closeButton.action = #selector(handleClose)
      contentStack.addArrangedSubview(closeButton)

      let contentLeading = contentStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: leadingAnchor,
        constant: 40
      )
      let contentTrailing = contentStack.trailingAnchor.constraint(
        lessThanOrEqualTo: trailingAnchor,
        constant: -40
      )
      let contentTop = contentStack.topAnchor.constraint(
        greaterThanOrEqualTo: topAnchor,
        constant: 40
      )
      let contentBottom = contentStack.bottomAnchor.constraint(
        lessThanOrEqualTo: bottomAnchor,
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
      previousMetadataWidthConstraint?.priority = NSLayoutConstraint.Priority(999)
      nextMetadataWidthConstraint?.priority = NSLayoutConstraint.Priority(999)

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
        previousTitleLabel.widthAnchor.constraint(equalTo: previousMetadataStack.widthAnchor),
        previousDetailLabel.widthAnchor.constraint(equalTo: previousMetadataStack.widthAnchor),

        nextStack.leadingAnchor.constraint(equalTo: nextContainer.leadingAnchor),
        nextStack.trailingAnchor.constraint(equalTo: nextContainer.trailingAnchor),
        nextStack.topAnchor.constraint(equalTo: nextContainer.topAnchor),
        nextStack.bottomAnchor.constraint(equalTo: nextContainer.bottomAnchor),
        nextMetadataStack.widthAnchor.constraint(lessThanOrEqualTo: nextStack.widthAnchor),
        nextMetadataWidthConstraint!,
        nextTitleLabel.widthAnchor.constraint(equalTo: nextMetadataStack.widthAnchor),
        nextDetailLabel.widthAnchor.constraint(equalTo: nextMetadataStack.widthAnchor),
        nextUnreadLabel.widthAnchor.constraint(equalTo: nextMetadataStack.widthAnchor),

        previousCoverWidthConstraint!,
        previousCoverHeightConstraint!,
        nextCoverWidthConstraint!,
        nextCoverHeightConstraint!,
      ])
    }

    private func applyConfiguration() {
      let textColor = NSColor(renderConfig.readerBackground.contentColor)
      let presentation = NativeEndPagePresentation.make(
        previousBook: previousBook,
        nextBook: nextBook,
        readListContext: readListContext,
        sectionDisplayMode: sectionDisplayMode,
        nextBookOfflineState: nextBookOfflineState,
        remainingUnreadCount: remainingUnreadCount
      )
      let relationTitle = presentation.relationTitle

      applyAppearanceColors()

      dividerTitleLabel.stringValue = relationTitle
      dividerTitleLabel.isHidden = relationTitle.isEmpty

      let metrics = NativeEndPageLayoutMetrics.resolve(for: bounds)
      previousBadgeLabel.font = metrics.badgeFont
      previousTitleLabel.font = metrics.titleFont
      previousDetailLabel.font = metrics.detailFont
      nextBadgeLabel.font = metrics.badgeFont
      nextTitleLabel.font = metrics.titleFont
      nextDetailLabel.font = metrics.detailFont
      nextUnreadLabel.font = metrics.detailFont
      caughtUpLabel.font = NSFont.preferredFont(forTextStyle: .headline)
      caughtUpUnreadLabel.font = metrics.detailFont
      dividerTitleLabel.font = NSFont.preferredFont(forTextStyle: .caption1)

      previousBadgeLabel.textColor = textColor.withAlphaComponent(0.55)
      previousTitleLabel.textColor = textColor
      previousDetailLabel.textColor = textColor.withAlphaComponent(0.6)
      nextBadgeLabel.textColor = textColor.withAlphaComponent(0.55)
      nextTitleLabel.textColor = textColor
      nextDetailLabel.textColor = textColor.withAlphaComponent(0.6)
      nextUnreadLabel.textColor = textColor.withAlphaComponent(0.6)
      nextProgressCircle.color = textColor
      nextStatusIconView.contentTintColor = textColor.withAlphaComponent(0.6)
      caughtUpIconView.contentTintColor = textColor
      caughtUpLabel.textColor = textColor
      caughtUpUnreadLabel.textColor = textColor.withAlphaComponent(0.6)
      dividerTitleLabel.textColor = textColor.withAlphaComponent(0.8)
      previousCoverView.imageBlendTintColor = coverBlendTintColor
      nextCoverView.imageBlendTintColor = coverBlendTintColor

      previousBadgeLabel.stringValue = String(localized: "reader.previousBook").uppercased()
      nextBadgeLabel.stringValue = presentation.next.badgeText ?? ""

      if presentation.previous.isVisible {
        previousContainer.isHidden = false
        previousCoverView.isHidden = !presentation.previous.showsCover
        previousTitleLabel.stringValue = presentation.previous.title ?? ""
        previousDetailLabel.stringValue = presentation.previous.detail ?? ""
        previousCoverView.configure(bookID: presentation.previous.bookID)
      } else {
        previousContainer.isHidden = true
        previousCoverView.isHidden = true
        previousTitleLabel.stringValue = ""
        previousDetailLabel.stringValue = ""
        previousCoverView.configure(bookID: nil)
      }

      if presentation.next.isVisible {
        nextContainer.isHidden = false
        nextBadgeLabel.isHidden = presentation.next.badgeText == nil
        nextCoverView.isHidden = !presentation.next.showsCover
        nextMetadataStack.isHidden = !presentation.next.showsMetadata
        caughtUpContainer.isHidden = !presentation.next.showsCaughtUp
        caughtUpLabel.stringValue = presentation.next.showsCaughtUp ? String(localized: "You're all caught up!") : ""
        nextTitleLabel.stringValue = presentation.next.title ?? ""
        nextDetailLabel.stringValue = presentation.next.detail ?? ""
        let unreadText = presentation.next.unreadRemainingText
        nextUnreadLabel.stringValue = presentation.next.showsMetadata ? unreadText ?? "" : ""
        nextUnreadLabel.isHidden = !presentation.next.showsMetadata || unreadText == nil
        caughtUpUnreadLabel.stringValue = presentation.next.showsCaughtUp ? unreadText ?? "" : ""
        caughtUpUnreadLabel.isHidden = !presentation.next.showsCaughtUp || unreadText == nil
        nextCoverView.configure(bookID: presentation.next.bookID)
        applyNextDownload(presentation.next.nextBookOfflineState)
      } else {
        nextContainer.isHidden = true
        nextBadgeLabel.isHidden = true
        nextCoverView.isHidden = true
        nextMetadataStack.isHidden = true
        caughtUpContainer.isHidden = true
        caughtUpLabel.stringValue = ""
        nextTitleLabel.stringValue = ""
        nextDetailLabel.stringValue = ""
        nextUnreadLabel.stringValue = ""
        nextUnreadLabel.isHidden = true
        caughtUpUnreadLabel.stringValue = ""
        caughtUpUnreadLabel.isHidden = true
        nextCoverView.configure(bookID: nil)
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
      setArrangedSubviews(
        of: contentStack,
        with: [
          showsRelationHeader ? horizontalDividerStack : nil,
          sectionsStack,
          closeButton,
        ]
      )

      switch presentation.layoutMode(for: bounds.size, readingDirection: readingDirection) {
      case .singlePrevious:
        sectionsStack.orientation = .vertical
        sectionsStack.alignment = .centerX
        previousCoverView.isHidden = previousBook == nil
        setArrangedSubviews(of: sectionsStack, with: [previousContainer])
      case .singleNext:
        sectionsStack.orientation = .vertical
        sectionsStack.alignment = .centerX
        previousCoverView.isHidden = true
        setArrangedSubviews(of: sectionsStack, with: [nextContainer])
      case .stacked:
        sectionsStack.orientation = .vertical
        sectionsStack.alignment = .centerX
        previousCoverView.isHidden = true
        setArrangedSubviews(
          of: sectionsStack,
          with: [previousContainer, horizontalDividerStack, nextContainer]
        )
      case .sideBySide(let nextOnLeadingSide, _):
        // Top-align the columns: the next-book side can grow a download
        // progress row, and center alignment would lift its cover/title
        // above the previous book's.
        sectionsStack.orientation = .horizontal
        sectionsStack.alignment = .top
        previousCoverView.isHidden = previousBook == nil
        if nextOnLeadingSide {
          setArrangedSubviews(
            of: sectionsStack,
            with: [nextContainer, verticalDivider, previousContainer]
          )
        } else {
          setArrangedSubviews(
            of: sectionsStack,
            with: [previousContainer, verticalDivider, nextContainer]
          )
        }
      }

      updateSectionsEqualWidthConstraint()
    }

    private func setArrangedSubviews(of stack: NSStackView, with views: [NSView?]) {
      let filteredViews = views.compactMap { $0 }
      if stack.arrangedSubviews.elementsEqual(filteredViews, by: { $0 === $1 }) {
        return
      }

      sectionsEqualWidthConstraint?.isActive = false
      stack.setViews([], in: .center)
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
      sectionsEqualWidthConstraint?.isActive = sectionsStack.orientation == .horizontal
    }

    private func applyDynamicMetrics() {
      guard bounds.width > 0, bounds.height > 0 else { return }

      let isPortrait = bounds.height >= bounds.width
      let metrics = NativeEndPageLayoutMetrics.resolve(for: bounds)

      contentStack.spacing = metrics.stackSpacing
      sectionsStack.spacing = isPortrait ? metrics.portraitSectionSpacing : metrics.stackSpacing

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

    private var shouldUseLightCoverShadow: Bool {
      switch renderConfig.readerBackground {
      case .black, .gray:
        return true
      case .white, .sepia:
        return false
      case .system:
        let bestMatch = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua
      }
    }

    private var coverBlendTintColor: NSColor? {
      renderConfig.readerBackground.appliesImageMultiplyBlend ? NSColor(renderConfig.readerBackground.color) : nil
    }

    @objc private func handleClose() {
      onDismiss?()
    }

    private func applyNextDownload(_ state: NextBookOfflineState?) {
      // Streaming readers never download ahead: collapse the slot entirely
      // instead of leaving a permanent empty band under the next book.
      nextDownloadStack.isHidden = !AppConfig.offlineFirstReading
      guard AppConfig.offlineFirstReading else {
        nextDownloadStack.alphaValue = 0
        return
      }
      nextDownloadStack.alphaValue = 1
      // Alpha, never isHidden below this point: the reserved slot must keep
      // the exact same height in every state, or the end page layout shifts.
      switch state {
      case .downloading(_, let progress)?:
        nextProgressCircle.alphaValue = 1
        nextStatusIconView.alphaValue = 0
        nextProgressCircle.progress = progress ?? 0
        let percent = (progress ?? 0).formatted(.percent.precision(.fractionLength(0)))
        nextStatusContainer.setAccessibilityLabel(
          String(localized: "Downloading next book…") + " \(percent)"
        )
      case .ready?:
        nextProgressCircle.alphaValue = 0
        nextStatusIconView.alphaValue = 1
        nextStatusIconView.image = NSImage(
          systemSymbolName: AppIcon.downloaded,
          accessibilityDescription: nil
        )
        nextStatusContainer.setAccessibilityLabel(String(localized: "Ready for offline reading"))
      case nil:
        nextProgressCircle.alphaValue = 0
        nextStatusIconView.alphaValue = 1
        nextStatusIconView.image = NSImage(
          systemSymbolName: AppIcon.downloadPartial,
          accessibilityDescription: nil
        )
        nextStatusContainer.setAccessibilityLabel(String(localized: "status.not_downloaded"))
      }
    }
  }
#endif
