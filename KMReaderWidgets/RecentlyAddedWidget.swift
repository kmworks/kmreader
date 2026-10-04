//
//  RecentlyAddedWidget.swift
//  KMReaderWidgets
//

import SwiftUI
import WidgetKit

struct RecentlyAddedEntry: TimelineEntry {
  let date: Date
  let books: [WidgetBookEntry]
}

struct RecentlyAddedProvider: TimelineProvider {
  func placeholder(in context: Context) -> RecentlyAddedEntry {
    RecentlyAddedEntry(date: .now, books: WidgetSampleData.books)
  }

  func getSnapshot(in context: Context, completion: @escaping (RecentlyAddedEntry) -> Void) {
    let books = WidgetDataStore.loadEntries(forKey: WidgetDataStore.recentlyAdded.storageKey)
    completion(RecentlyAddedEntry(date: .now, books: books))
  }

  func getTimeline(
    in context: Context, completion: @escaping (Timeline<RecentlyAddedEntry>) -> Void
  ) {
    let books = WidgetDataStore.loadEntries(forKey: WidgetDataStore.recentlyAdded.storageKey)
    let entry = RecentlyAddedEntry(date: .now, books: books)
    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
  }
}

struct RecentlyAddedWidgetEntryView: View {
  @Environment(\.widgetFamily) var widgetFamily
  let entry: RecentlyAddedEntry

  var body: some View {
    if entry.books.isEmpty {
      emptyView
    } else {
      switch widgetFamily {
      case .systemSmall:
        WidgetBookCardView(entry: entry.books[0], showProgress: false)
      case .systemMedium:
        mediumView
      case .systemLarge:
        largeView
      default:
        WidgetBookCardView(entry: entry.books[0], showProgress: false)
      }
    }
  }

  private var emptyView: some View {
    VStack(spacing: 8) {
      Image(systemName: "plus.square.on.square")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text(String(localized: "widget.no_books"))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var mediumView: some View {
    let books = Array(entry.books.prefix(3))
    return HStack(spacing: 8) {
      ForEach(books, id: \.id) { book in
        WidgetBookCardView(entry: book, showProgress: false)
          .frame(maxWidth: .infinity)
      }
      ForEach(0..<(3 - books.count), id: \.self) { _ in
        Color.clear
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var largeView: some View {
    let books = Array(entry.books.prefix(6))
    let topRow = Array(books.prefix(3))
    let bottomRow = Array(books.dropFirst(3))
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        ForEach(topRow, id: \.id) { book in
          WidgetBookCardView(entry: book, showProgress: false)
            .frame(maxWidth: .infinity)
        }
      }
      if !bottomRow.isEmpty {
        HStack(spacing: 8) {
          ForEach(bottomRow, id: \.id) { book in
            WidgetBookCardView(entry: book, showProgress: false)
              .frame(maxWidth: .infinity)
          }
          ForEach(0..<(3 - bottomRow.count), id: \.self) { _ in
            Color.clear
              .frame(maxWidth: .infinity)
          }
        }
      }
    }
  }
}

struct RecentlyAddedWidget: Widget {
  let kind = WidgetDataStore.recentlyAdded.kind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: RecentlyAddedProvider()) { entry in
      RecentlyAddedWidgetEntryView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName(String(localized: "widget.recently_added.title"))
    .description(String(localized: "widget.recently_added.description"))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
