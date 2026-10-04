//
//  RecentlyUpdatedSeriesWidget.swift
//  KMReaderWidgets
//

import SwiftUI
import WidgetKit

struct RecentlyUpdatedSeriesEntry: TimelineEntry {
  let date: Date
  let series: [WidgetSeriesEntry]
}

struct RecentlyUpdatedSeriesProvider: TimelineProvider {
  func placeholder(in context: Context) -> RecentlyUpdatedSeriesEntry {
    RecentlyUpdatedSeriesEntry(date: .now, series: WidgetSampleData.series)
  }

  func getSnapshot(in context: Context, completion: @escaping (RecentlyUpdatedSeriesEntry) -> Void) {
    let series = WidgetDataStore.loadSeriesEntries(forKey: WidgetDataStore.recentlyUpdatedSeries.storageKey)
    completion(RecentlyUpdatedSeriesEntry(date: .now, series: series))
  }

  func getTimeline(
    in context: Context, completion: @escaping (Timeline<RecentlyUpdatedSeriesEntry>) -> Void
  ) {
    let series = WidgetDataStore.loadSeriesEntries(forKey: WidgetDataStore.recentlyUpdatedSeries.storageKey)
    let entry = RecentlyUpdatedSeriesEntry(date: .now, series: series)
    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
  }
}

struct RecentlyUpdatedSeriesWidgetEntryView: View {
  @Environment(\.widgetFamily) var widgetFamily
  let entry: RecentlyUpdatedSeriesEntry

  var body: some View {
    if entry.series.isEmpty {
      emptyView
    } else {
      switch widgetFamily {
      case .systemSmall:
        WidgetSeriesCardView(entry: entry.series[0])
      case .systemMedium:
        mediumView
      case .systemLarge:
        largeView
      default:
        WidgetSeriesCardView(entry: entry.series[0])
      }
    }
  }

  private var emptyView: some View {
    VStack(spacing: 8) {
      Image(systemName: "clock.arrow.circlepath")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text(String(localized: "widget.no_series"))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var mediumView: some View {
    let series = Array(entry.series.prefix(3))
    return HStack(spacing: 8) {
      ForEach(series, id: \.id) { item in
        WidgetSeriesCardView(entry: item)
          .frame(maxWidth: .infinity)
      }
      ForEach(0..<(3 - series.count), id: \.self) { _ in
        Color.clear
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var largeView: some View {
    let series = Array(entry.series.prefix(6))
    let topRow = Array(series.prefix(3))
    let bottomRow = Array(series.dropFirst(3))
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        ForEach(topRow, id: \.id) { item in
          WidgetSeriesCardView(entry: item)
            .frame(maxWidth: .infinity)
        }
      }
      if !bottomRow.isEmpty {
        HStack(spacing: 8) {
          ForEach(bottomRow, id: \.id) { item in
            WidgetSeriesCardView(entry: item)
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

struct RecentlyUpdatedSeriesWidget: Widget {
  let kind = WidgetDataStore.recentlyUpdatedSeries.kind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: RecentlyUpdatedSeriesProvider()) { entry in
      RecentlyUpdatedSeriesWidgetEntryView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName(String(localized: "widget.recently_updated_series.title"))
    .description(String(localized: "widget.recently_updated_series.description"))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
