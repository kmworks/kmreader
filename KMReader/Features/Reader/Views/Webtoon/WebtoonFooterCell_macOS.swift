//
// WebtoonFooterCell_macOS.swift
//
//

#if os(macOS)
  import AppKit
  import SwiftUI

  class WebtoonFooterCell: NSCollectionViewItem {
    var readerBackground: ReaderBackground = .system {
      didSet { applyBackground() }
    }

    private var previousBook: Book?
    private var nextBook: Book?
    private var nextBookOfflineState: NextBookOfflineState?
    private var readListContext: ReaderReadListContext?
    private var onDismiss: (() -> Void)?

    private let topRegionView = NSView()
    private let bottomRegionView = NSView()
    private let previousBookStack = NSStackView()
    private let previousBadgeLabel = NSTextField(labelWithString: "")
    private let previousTitleLabel = NSTextField(labelWithString: "")
    private let previousDetailLabel = NSTextField(labelWithString: "")

    private let dividerStack = NSStackView()
    private let leadingDivider = NSView()
    private let dividerTitleLabel = NSTextField(labelWithString: "")
    private let trailingDivider = NSView()

    private let nextBookStack = NSStackView()
    private let nextBadgeLabel = NSTextField(labelWithString: "")
    private let nextTitleLabel = NSTextField(labelWithString: "")
    private let nextDetailLabel = NSTextField(labelWithString: "")
    private let nextDownloadStack = NSStackView()
    private let nextStatusContainer = NSView()
    private let nextProgressCircle = CircularProgressView()
    private let nextStatusIconView = NSImageView()
    private let caughtUpLabel = NSTextField(labelWithString: "")

    private let closeButton = NSButton()

    override func loadView() {
      view = NSView()
      view.wantsLayer = true
      setupUI()
    }

    func configure(
      previousBook: Book?,
      nextBook: Book?,
      readListContext: ReaderReadListContext?,
      nextBookOfflineState: NextBookOfflineState? = nil,
      onDismiss: (() -> Void)?
    ) {
      self.previousBook = previousBook
      self.nextBook = nextBook
      self.nextBookOfflineState = nextBookOfflineState
      self.readListContext = readListContext
      self.onDismiss = onDismiss
      applyContent()
    }

    private func setupUI() {
      topRegionView.translatesAutoresizingMaskIntoConstraints = false
      bottomRegionView.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(topRegionView)
      view.addSubview(bottomRegionView)

      previousBookStack.orientation = .vertical
      previousBookStack.alignment = .centerX
      previousBookStack.spacing = 6
      previousBookStack.translatesAutoresizingMaskIntoConstraints = false
      previousBookStack.setContentHuggingPriority(.required, for: .vertical)
      previousBookStack.setContentCompressionResistancePriority(.required, for: .vertical)
      topRegionView.addSubview(previousBookStack)

      previousBadgeLabel.alignment = .center
      previousBadgeLabel.maximumNumberOfLines = 1
      previousBadgeLabel.font = NSFont.preferredFont(forTextStyle: .caption1)
      previousBadgeLabel.stringValue = String(localized: "reader.previousBook").uppercased()
      previousBookStack.addArrangedSubview(previousBadgeLabel)

      previousTitleLabel.alignment = .center
      previousTitleLabel.maximumNumberOfLines = 2
      previousTitleLabel.font = NSFont.preferredFont(forTextStyle: .title3)
      previousBookStack.addArrangedSubview(previousTitleLabel)

      previousDetailLabel.alignment = .center
      previousDetailLabel.maximumNumberOfLines = 1
      previousDetailLabel.font = NSFont.preferredFont(forTextStyle: .caption1)
      previousBookStack.addArrangedSubview(previousDetailLabel)

      dividerStack.orientation = .horizontal
      dividerStack.alignment = .centerY
      dividerStack.spacing = 10
      dividerStack.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(dividerStack)

      leadingDivider.wantsLayer = true
      leadingDivider.translatesAutoresizingMaskIntoConstraints = false
      leadingDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
      leadingDivider.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
      dividerStack.addArrangedSubview(leadingDivider)

      dividerTitleLabel.alignment = .center
      dividerTitleLabel.maximumNumberOfLines = 1
      dividerTitleLabel.font = NSFont.preferredFont(forTextStyle: .caption1)
      dividerStack.addArrangedSubview(dividerTitleLabel)

      trailingDivider.wantsLayer = true
      trailingDivider.translatesAutoresizingMaskIntoConstraints = false
      trailingDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
      trailingDivider.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
      dividerStack.addArrangedSubview(trailingDivider)

      nextBookStack.orientation = .vertical
      nextBookStack.alignment = .centerX
      nextBookStack.spacing = 6
      nextBookStack.translatesAutoresizingMaskIntoConstraints = false
      nextBookStack.setContentHuggingPriority(.required, for: .vertical)
      nextBookStack.setContentCompressionResistancePriority(.required, for: .vertical)
      bottomRegionView.addSubview(nextBookStack)

      nextBadgeLabel.alignment = .center
      nextBadgeLabel.maximumNumberOfLines = 1
      nextBadgeLabel.font = NSFont.preferredFont(forTextStyle: .caption1)
      nextBadgeLabel.stringValue = String(localized: "reader.nextBook").uppercased()
      nextBookStack.addArrangedSubview(nextBadgeLabel)

      nextTitleLabel.alignment = .center
      nextTitleLabel.maximumNumberOfLines = 2
      nextTitleLabel.font = NSFont.preferredFont(forTextStyle: .title3)
      nextBookStack.addArrangedSubview(nextTitleLabel)

      nextDetailLabel.alignment = .center
      nextDetailLabel.maximumNumberOfLines = 1
      nextDetailLabel.font = NSFont.preferredFont(forTextStyle: .caption1)
      nextBookStack.addArrangedSubview(nextDetailLabel)

      nextDownloadStack.orientation = .vertical
      nextDownloadStack.alignment = .centerX
      nextDownloadStack.spacing = 6
      // Reserved slot (offline-first only) inside the stack: the footer has a
      // fixed height, and the slot always occupies its space so the download
      // state never re-lays out (and visibly shifts) the next-book block.
      nextDownloadStack.alphaValue = 0
      nextDownloadStack.translatesAutoresizingMaskIntoConstraints = false
      nextBookStack.addArrangedSubview(nextDownloadStack)

      // Fixed-height status slot: one centered icon per state — a circular
      // progress pie while downloading, a hollow iCloud when the next book
      // is not on device, and a checked iCloud once it is. Every state keeps
      // the exact same height so the footer layout never shifts.
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

      caughtUpLabel.alignment = .center
      caughtUpLabel.maximumNumberOfLines = 2
      caughtUpLabel.font = NSFont.preferredFont(forTextStyle: .headline)
      nextBookStack.addArrangedSubview(caughtUpLabel)
      nextBookStack.setCustomSpacing(20, after: caughtUpLabel)

      closeButton.bezelStyle = .rounded
      closeButton.target = self
      closeButton.action = #selector(handleClose)
      nextBookStack.addArrangedSubview(closeButton)

      NSLayoutConstraint.activate([
        dividerStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        dividerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 44),
        dividerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44),

        topRegionView.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
        topRegionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 44),
        topRegionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44),
        topRegionView.bottomAnchor.constraint(equalTo: dividerStack.topAnchor, constant: -12),

        bottomRegionView.topAnchor.constraint(equalTo: dividerStack.bottomAnchor, constant: 12),
        bottomRegionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 44),
        bottomRegionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44),
        bottomRegionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32),

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
      view.layer?.backgroundColor = NSColor(readerBackground.color).cgColor
      let textColor = NSColor(readerBackground.contentColor)
      previousBadgeLabel.textColor = textColor.withAlphaComponent(0.55)
      previousTitleLabel.textColor = textColor
      previousDetailLabel.textColor = textColor.withAlphaComponent(0.6)
      dividerTitleLabel.textColor = textColor.withAlphaComponent(0.8)
      leadingDivider.layer?.backgroundColor = textColor.withAlphaComponent(0.3).cgColor
      trailingDivider.layer?.backgroundColor = textColor.withAlphaComponent(0.3).cgColor
      nextBadgeLabel.textColor = textColor.withAlphaComponent(0.55)
      nextTitleLabel.textColor = textColor
      nextDetailLabel.textColor = textColor.withAlphaComponent(0.6)
      nextProgressCircle.color = textColor
      nextStatusIconView.contentTintColor = textColor.withAlphaComponent(0.6)
      caughtUpLabel.textColor = textColor
      EndPageCloseButtonStyle.apply(to: closeButton, textColor: textColor)
    }

    private func applyContent() {
      dividerTitleLabel.stringValue =
        readListContext?.name ?? previousBook?.seriesTitle ?? nextBook?.seriesTitle ?? ""

      if let previousBook {
        previousBookStack.isHidden = false
        previousTitleLabel.stringValue = previousBook.readerChapterTitle
        previousDetailLabel.stringValue = previousBook.readerChapterDetail
      } else {
        previousBookStack.isHidden = true
      }

      if let nextBook {
        closeButton.isHidden = true
        nextBadgeLabel.isHidden = false
        caughtUpLabel.isHidden = true
        nextTitleLabel.isHidden = false
        nextDetailLabel.isHidden = false
        nextTitleLabel.stringValue = nextBook.readerChapterTitle
        nextDetailLabel.stringValue = nextBook.readerChapterDetail
        applyNextDownload(nextBookOfflineState)
      } else {
        closeButton.isHidden = false
        nextBadgeLabel.isHidden = true
        nextTitleLabel.isHidden = true
        nextDetailLabel.isHidden = true
        nextTitleLabel.stringValue = ""
        nextDetailLabel.stringValue = ""
        // Caught up: no next book, so the download slot has nothing to show.
        nextDownloadStack.isHidden = true
        caughtUpLabel.isHidden = false
        caughtUpLabel.stringValue = String(localized: "You're all caught up!")
      }

      EndPageCloseButtonStyle.apply(to: closeButton, textColor: NSColor(readerBackground.contentColor))
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
      // the exact same height in every state, or the footer layout shifts.
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
          systemSymbolName: "checkmark.icloud.fill",
          accessibilityDescription: nil
        )
        nextStatusContainer.setAccessibilityLabel(String(localized: "Ready for offline reading"))
      case nil:
        nextProgressCircle.alphaValue = 0
        nextStatusIconView.alphaValue = 1
        nextStatusIconView.image = NSImage(
          systemSymbolName: "icloud",
          accessibilityDescription: nil
        )
        nextStatusContainer.setAccessibilityLabel(String(localized: "status.not_downloaded"))
      }
    }

    func isInteractingWithCloseButton(at point: NSPoint, in sourceView: NSView) -> Bool {
      guard !closeButton.isHidden else { return false }
      let localPoint = closeButton.convert(point, from: sourceView)
      return closeButton.bounds.contains(localPoint)
    }

    @objc private func handleClose() {
      onDismiss?()
    }
  }
#endif
