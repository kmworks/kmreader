//
// BookSelectionItemView.swift
//
//

import SwiftUI

/// View for book selection mode that accepts only bookId and fetches a book display projection.
struct BookSelectionItemView: View {
  let bookId: String
  let layout: BrowseLayoutMode
  @Binding var selectedBookIds: Set<String>
  var cardWidth: CGFloat = LayoutConfig.gridCardWidth
  var showSeriesTitle: Bool = true

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var item: BookDisplayItem?

  init(
    bookId: String,
    layout: BrowseLayoutMode,
    selectedBookIds: Binding<Set<String>>,
    cardWidth: CGFloat = LayoutConfig.gridCardWidth,
    showSeriesTitle: Bool = true
  ) {
    self.bookId = bookId
    self.layout = layout
    self._selectedBookIds = selectedBookIds
    self.cardWidth = cardWidth
    self.showSeriesTitle = showSeriesTitle

  }

  private var isSelected: Bool {
    selectedBookIds.contains(bookId)
  }

  var body: some View {
    selectionBody
      .allowsHitTesting(false)
      .animation(.appCurve(), value: isSelected)
      .contentShape(Rectangle())
      .highPriorityGesture(
        TapGesture().onEnded {
          if isSelected {
            selectedBookIds.remove(bookId)
          } else {
            selectedBookIds.insert(bookId)
          }
        }
      )
      .task(id: "\(current.instanceId)|\(bookId)") {
        await loadItem()
      }
      .onReceive(NotificationCenter.default.publisher(for: .bookProjectionDidChange)) {
        notification in
        guard shouldReload(for: notification) else { return }
        reloadItem()
      }
  }

  @ViewBuilder
  private var selectionBody: some View {
    switch layout {
    case .grid, .largeGrid:
      selectionContent
        .selectionDimmed(!isSelected, scale: 0.92)
    case .list:
      HStack(spacing: 12) {
        selectionContent
          .selectionDimmed(!isSelected, scale: 0.97)
        SelectionBadge(isSelected: isSelected)
      }
    }
  }

  @ViewBuilder
  private var selectionContent: some View {
    if let item {
      switch layout {
      case .grid, .largeGrid:
        BookCardView(
          item: item,
          onReadBook: { _ in },
          showSeriesTitle: showSeriesTitle,
          showCompletedIndicator: false,
          selectionIsSelected: isSelected,
          cardWidth: cardWidth
        )
      case .list:
        BookRowView(
          item: item,
          onReadBook: { _ in },
          showSeriesTitle: showSeriesTitle,
          showsEllipsis: false
        )
      }
    } else {
      CardPlaceholder(
        layout: layout,
        kind: .book,
        showBookSeriesTitle: showSeriesTitle
      )
    }
  }

  private func shouldReload(for notification: Notification) -> Bool {
    if notification.userInfo?["bookId"] as? String == bookId {
      return true
    }
    if let bookIds = notification.userInfo?["bookIds"] as? Set<String> {
      return bookIds.contains(bookId)
    }
    if let bookIds = notification.userInfo?["bookIds"] as? [String] {
      return bookIds.contains(bookId)
    }
    return false
  }

  private func reloadItem() {
    Task {
      await loadItem()
    }
  }

  private func loadItem() async {
    guard let database = try? await DatabaseOperator.database() else {
      item = nil
      return
    }
    item = try? await database.fetchBookDisplayItem(
      bookId: bookId,
      instanceId: current.instanceId
    )
  }
}
