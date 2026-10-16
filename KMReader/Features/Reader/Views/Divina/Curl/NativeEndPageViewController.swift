//
// NativeEndPageViewController.swift
//

#if os(iOS)
  import SwiftUI
  import UIKit

  @MainActor
  final class NativeEndPageViewController: UIViewController {
    enum SectionDisplayMode {
      case both
      case previousOnly
      case nextOnly
    }

    private let endPageView = NativeEndPageContentView()

    override func loadView() {
      view = endPageView
    }

    func configure(
      previousBook: Book?,
      nextBook: Book?,
      readListContext: ReaderReadListContext?,
      readingDirection: ReadingDirection,
      sectionDisplayMode: SectionDisplayMode = .both,
      renderConfig: ReaderRenderConfig,
      nextBookOfflineState: NextBookOfflineState? = nil,
      remainingUnreadCount: Int? = nil,
      onDismiss: @escaping () -> Void
    ) {
      endPageView.configure(
        previousBook: previousBook,
        nextBook: nextBook,
        readListContext: readListContext,
        readingDirection: readingDirection,
        sectionDisplayMode: presentationSectionDisplayMode(for: sectionDisplayMode),
        renderConfig: renderConfig,
        nextBookOfflineState: nextBookOfflineState,
        remainingUnreadCount: remainingUnreadCount,
        onDismiss: onDismiss
      )
    }

    private func presentationSectionDisplayMode(
      for sectionDisplayMode: SectionDisplayMode
    ) -> NativeEndPagePresentation.SectionDisplayMode {
      switch sectionDisplayMode {
      case .both:
        return .both
      case .previousOnly:
        return .previousOnly
      case .nextOnly:
        return .nextOnly
      }
    }
  }
#endif
