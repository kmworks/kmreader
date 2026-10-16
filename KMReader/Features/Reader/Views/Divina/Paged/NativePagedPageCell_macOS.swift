#if os(macOS)
  import AppKit
  import SwiftUI

  final class NativePagedPageCell: NSCollectionViewItem {
    private let pagedContentView = NativePagedPageContentView()

    override func loadView() {
      view = NSView()
      view.wantsLayer = true
      view.addSubview(pagedContentView)
      pagedContentView.translatesAutoresizingMaskIntoConstraints = false

      NSLayoutConstraint.activate([
        pagedContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        pagedContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        pagedContentView.topAnchor.constraint(equalTo: view.topAnchor),
        pagedContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
    }

    func configure(
      viewModel: ReaderViewModel,
      item: ReaderViewItem,
      screenSize: CGSize,
      renderConfig: ReaderRenderConfig,
      readingDirection: ReadingDirection,
      splitWidePageMode: SplitWidePageMode,
      isPlaybackActive: Bool
    ) {
      pagedContentView.configure(
        viewModel: viewModel,
        item: item,
        screenSize: screenSize,
        renderConfig: renderConfig,
        readingDirection: readingDirection,
        splitWidePageMode: splitWidePageMode,
        isPlaybackActive: isPlaybackActive,
        tracksGlobalZoomState: true
      )
    }

    func updatePlaybackActive(_ isPlaybackActive: Bool) {
      pagedContentView.updatePlaybackActive(isPlaybackActive)
    }

    func resetContent(backgroundColor: NSColor) {
      view.wantsLayer = true
      view.layer?.backgroundColor = backgroundColor.cgColor
      pagedContentView.resetContent(backgroundColor: backgroundColor)
    }

    override func prepareForReuse() {
      super.prepareForReuse()
      pagedContentView.resetContent()
    }
  }
#endif
