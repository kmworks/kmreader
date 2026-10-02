#if os(macOS)
  import AppKit
  import SwiftUI

  final class NativePagedEndCell: NSCollectionViewItem {
    private let endPageView = NativeEndPageContentView()

    override func loadView() {
      view = NSView()
      setupUI()
    }

    override func prepareForReuse() {
      super.prepareForReuse()
      endPageView.configure(
        previousBook: nil,
        nextBook: nil,
        readListContext: nil,
        readingDirection: .ltr,
        renderConfig: placeholderRenderConfig,
        onDismiss: nil
      )
    }

    func configure(
      previousBook: Book?,
      nextBook: Book?,
      readListContext: ReaderReadListContext?,
      readingDirection: ReadingDirection,
      renderConfig: ReaderRenderConfig,
      nextBookOfflineState: NextBookOfflineState? = nil,
      remainingUnreadCount: Int? = nil,
      onDismiss: (() -> Void)?
    ) {
      endPageView.configure(
        previousBook: previousBook,
        nextBook: nextBook,
        readListContext: readListContext,
        readingDirection: readingDirection,
        renderConfig: renderConfig,
        nextBookOfflineState: nextBookOfflineState,
        remainingUnreadCount: remainingUnreadCount,
        onDismiss: onDismiss
      )
    }

    private func setupUI() {
      view.addSubview(endPageView)
      endPageView.translatesAutoresizingMaskIntoConstraints = false

      NSLayoutConstraint.activate([
        endPageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        endPageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        endPageView.topAnchor.constraint(equalTo: view.topAnchor),
        endPageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
    }

    private var placeholderRenderConfig: ReaderRenderConfig {
      ReaderRenderConfig(
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
    }
  }
#endif
