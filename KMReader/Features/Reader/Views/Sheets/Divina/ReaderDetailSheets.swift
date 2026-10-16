//
// ReaderDetailSheets.swift
//
//

import SwiftUI

extension View {
  func readerDetailSheet(
    isPresented: Binding<Bool>,
    book: Book?,
    series: Series?
  ) -> some View {
    self.sheet(isPresented: isPresented) {
      if let book = book, let series = series {
        ReaderDetailSheetContent(book: book, series: series)
      }
    }
  }
}

private struct ReaderDetailSheetContent: View {
  /// Seed values from the reader's load-time state; the sheet re-reads the
  /// local projection on presentation so progress recorded since the book
  /// loaded (e.g. the just-finished book) is reflected.
  @State private var book: Book
  @State private var series: Series
  @State private var showingSeries: Bool = false

  init(book: Book, series: Series) {
    _book = State(initialValue: book)
    _series = State(initialValue: series)
  }

  private var title: String {
    if showingSeries {
      series.metadata.title
    } else {
      book.metadata.title
    }
  }

  var body: some View {
    SheetView(title: title, size: .large) {
      ScrollView {
        Group {
          if book.oneshot {
            OneShotDetailContentView(
              book: book,
              series: series,
              downloadStatus: nil,
              inSheet: true
            )
          } else {
            if showingSeries {
              SeriesDetailContentView(
                series: series
              ) {
                EmptyView()
              }
            } else {
              BookDetailContentView(
                book: book,
                downloadStatus: nil,
                inSheet: true
              )
            }
          }
        }.padding(.horizontal)
      }
    } controls: {
      if !book.oneshot {
        Button {
          withAnimation {
            showingSeries.toggle()
          }
        } label: {
          Image(systemName: showingSeries ? ContentIcon.book : ContentIcon.series)
        }
      }
    }
    .task {
      let database = await DatabaseOperator.databaseIfConfigured()
      if let freshBook = await database?.fetchBook(id: book.id) {
        book = freshBook
      }
      if let freshSeries = await database?.fetchSeries(id: series.id) {
        series = freshSeries
      }
    }
  }
}
