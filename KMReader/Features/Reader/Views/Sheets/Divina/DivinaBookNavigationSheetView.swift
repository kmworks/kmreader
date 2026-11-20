//
// DivinaBookNavigationSheetView.swift
//
//

import SwiftUI

struct DivinaBookNavigationSheetView: View {
  let books: [Book]
  let currentBookId: String
  let collectionTitle: String?
  let showsSeriesTitle: Bool
  let onSelect: (Book) -> Void

  var body: some View {
    SheetView(title: String(localized: "Book Navigation"), size: .large, applyFormStyle: true) {
      ScrollViewReader { proxy in
        List {
          if let collectionTitle, !collectionTitle.isEmpty {
            Section {
              bookRows
            } header: {
              Text(collectionTitle)
            }
          } else {
            bookRows
          }
        }
        .optimizedListStyle()
        .onAppear {
          scrollToCurrentBook(proxy: proxy)
        }
        .onChange(of: books.map(\.id)) {
          scrollToCurrentBook(proxy: proxy)
        }
      }
    }
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder
  private var bookRows: some View {
    ForEach(books) { book in
      bookRow(book)
    }
  }

  private func bookRow(_ book: Book) -> some View {
    let isCurrent = book.id == currentBookId

    return Button {
      onSelect(book)
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(book.oneshot ? book.metadata.title : "#\(book.metadata.number) - \(book.metadata.title)")
            .fontWeight(isCurrent ? .semibold : .regular)
            .lineLimit(2)
          if showsSeriesTitle && !book.seriesTitle.isEmpty {
            Text(book.seriesTitle)
              .font(.footnote)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)

        if isCurrent {
          Image(systemName: "bookmark.fill")
        }
      }
      .foregroundStyle(isCurrent ? .secondary : .primary)
      .contentShape(Rectangle())
    }
    .adaptiveButtonStyle(.plain)
    .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : nil)
    .id(book.id)
  }

  private func scrollToCurrentBook(proxy: ScrollViewProxy) {
    DispatchQueue.main.async {
      proxy.scrollTo(currentBookId, anchor: .center)
    }
  }
}
