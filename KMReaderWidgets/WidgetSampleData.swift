//
//  WidgetSampleData.swift
//  KMReaderWidgets
//

import Foundation

/// Sample entries for widget gallery placeholders, so previews render the
/// card layout instead of the empty state.
enum WidgetSampleData {
  static let books: [WidgetBookEntry] = [
    WidgetBookEntry(
      id: "sample-book-1",
      seriesId: "sample-series-1",
      title: "The Silent Library",
      seriesTitle: "The Silent Library",
      number: 1,
      progressPage: 42,
      totalPages: 180,
      progressCompleted: false,
      thumbnailFileName: nil,
      createdDate: .now
    ),
    WidgetBookEntry(
      id: "sample-book-2",
      seriesId: "sample-series-2",
      title: "Chronicles of Dawn",
      seriesTitle: "Chronicles of Dawn",
      number: 3,
      progressPage: 128,
      totalPages: 200,
      progressCompleted: false,
      thumbnailFileName: nil,
      createdDate: .now
    ),
    WidgetBookEntry(
      id: "sample-book-3",
      seriesId: "sample-series-3",
      title: "Midnight Voyage",
      seriesTitle: "Midnight Voyage",
      number: 2,
      progressPage: 7,
      totalPages: 96,
      progressCompleted: false,
      thumbnailFileName: nil,
      createdDate: .now
    ),
  ]

  static let series: [WidgetSeriesEntry] = [
    WidgetSeriesEntry(
      id: "sample-series-1",
      title: "The Silent Library",
      booksCount: 12,
      unreadCount: 3,
      lastModified: .now,
      thumbnailFileName: nil
    ),
    WidgetSeriesEntry(
      id: "sample-series-2",
      title: "Chronicles of Dawn",
      booksCount: 8,
      unreadCount: 1,
      lastModified: .now,
      thumbnailFileName: nil
    ),
    WidgetSeriesEntry(
      id: "sample-series-3",
      title: "Midnight Voyage",
      booksCount: 24,
      unreadCount: nil,
      lastModified: .now,
      thumbnailFileName: nil
    ),
  ]
}
