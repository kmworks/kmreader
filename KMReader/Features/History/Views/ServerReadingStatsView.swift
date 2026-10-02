//
// ServerReadingStatsView.swift
//
//

import Charts
import SwiftUI

struct ServerReadingStatsView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var selectedLibraryId: String = ""
  @State private var viewModel = ReadingStatsViewModel()
  @State private var selectedTimePointId: String?
  @State private var libraries: [SidebarLibraryItem] = []
  @State private var syncInfo: OfflineInstanceSyncInfo?

  private var shouldShowInitialSyncHint: Bool {
    // Server-side stats do not depend on the local sync state.
    guard viewModel.dataSource == .local else { return false }
    guard let syncInfo else { return false }
    let neverSyncedAt = Date(timeIntervalSince1970: 0)
    let hasNeverSynced =
      syncInfo.seriesLastSyncedAt == neverSyncedAt
      && syncInfo.booksLastSyncedAt == neverSyncedAt
    let hasAnyLocalBook = (viewModel.payload?.summary.totalBooks ?? 0) > 0
    return hasNeverSynced && !hasAnyLocalBook
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        controlsSection

        if let errorMessage = viewModel.errorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(.orange)
        }

        if shouldShowInitialSyncHint {
          Text(
            String(
              localized: "Local data has not been synced yet. Run offline sync first to generate reading stats."
            )
          )
          .font(.footnote)
          .foregroundStyle(.orange)
        }

        if viewModel.isLoading && viewModel.payload == nil {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
          .padding(.top, 24)
        } else if let payload = viewModel.payload {
          statsContent(payload: payload)
        } else {
          emptyState
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 12)
    }
    .platformNavigationTitle(ServerSection.readingStats.title)
    .task(id: current.instanceId) {
      selectedLibraryId = ""
      await loadLocalContext()
      await reload(forceRefresh: false)
    }
    .onChange(of: selectedLibraryId) { _, _ in
      Task {
        await reload(forceRefresh: false)
      }
    }
    .onChange(of: viewModel.selectedTimeRange) { _, _ in
      selectedTimePointId = nil
    }
    .onChange(of: isOffline) { oldValue, newValue in
      if oldValue && !newValue {
        Task {
          await loadLocalContext()
          await reload(forceRefresh: false)
        }
      }
    }
    #if os(iOS) || os(macOS)
      .refreshable {
        await reload(forceRefresh: true)
      }
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task {
            await reload(forceRefresh: true)
          }
        } label: {
          if viewModel.isRefreshing {
            ProgressView()
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .disabled(viewModel.isLoading || viewModel.isRefreshing)
      }
    }
  }

  private var controlsSection: some View {
    HStack(spacing: 8) {
      Picker(String(localized: "Library"), selection: $selectedLibraryId) {
        Text(String(localized: "All Libraries"))
          .tag("")
        ForEach(libraries) { library in
          Text(library.name)
            .tag(library.libraryId)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
      .lineLimit(1)
      .truncationMode(.tail)
      .layoutPriority(1)
      .accessibilityLabel(String(localized: "Library"))

      Spacer()

      if let lastUpdatedAt = viewModel.lastUpdatedAt {
        Text(lastUpdatedAt.formatted(date: .numeric, time: .shortened))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .fixedSize(horizontal: true, vertical: false)
      }

    }
    .padding(12)
    .background(.thinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "chart.bar.doc.horizontal")
        .font(.system(size: 36))
        .foregroundStyle(.secondary)
      Text(String(localized: "No reading stats available"))
        .font(.headline)
      Text(
        shouldShowInitialSyncHint
          ? String(
            localized: "Local data has not been synced yet. Run offline sync first to generate reading stats."
          )
          : String(localized: "Pull to refresh to recalculate reading stats from local data.")
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      Button {
        Task {
          await reload(forceRefresh: true)
        }
      } label: {
        Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
      }
      .adaptiveButtonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
  }

  @ViewBuilder
  private func statsContent(payload: ReadingStatsPayload) -> some View {
    let summary = payload.summary
    let heatmapWeeks = viewModel.readingPagesHeatmapWeeks()

    summarySection(summary)

    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Text(String(localized: "Pages Read"))
          .font(.headline)

        Spacer()

        Picker(String(localized: "Range"), selection: $viewModel.selectedTimeRange) {
          ForEach(ReadingStatsTimeRange.allCases, id: \.self) { range in
            Text(range.title)
              .tag(range)
          }
        }
        .pickerStyle(.menu)
      }

      if heatmapWeeks.isEmpty {
        sectionEmptyState(systemImage: "square.grid.3x3", message: String(localized: "No data"))
      } else {
        ReadingPagesHeatmapView(weeks: heatmapWeeks, selectedPointId: $selectedTimePointId)
      }
    }
    .padding(12)
    .background(.thinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))

    sectionCard(title: String(localized: "Reading Status")) {
      if payload.statusDistribution.isEmpty {
        sectionEmptyState(systemImage: "chart.bar", message: String(localized: "No data"))
      } else {
        pieChart(payload.statusDistribution)
      }
    }

    sectionCard(title: String(localized: "Reading by Weekday")) {
      if payload.dailyDistribution.isEmpty {
        sectionEmptyState(systemImage: "calendar", message: String(localized: "No data"))
      } else {
        distributionChart(payload.dailyDistribution, keepOrder: true, color: .blue)
      }
    }

    sectionCard(title: String(localized: "Reading by Hour")) {
      if payload.hourlyDistribution.isEmpty {
        sectionEmptyState(systemImage: "clock", message: String(localized: "No data"))
      } else {
        distributionChart(payload.hourlyDistribution, keepOrder: true, sparseAxisLabels: true, color: .teal)
      }
    }

    topItemsSection(title: String(localized: "Top Authors"), items: payload.topAuthors)
    topItemsSection(title: String(localized: "Top Genres"), items: payload.topGenres)
    topItemsSection(title: String(localized: "Top Tags"), items: payload.topTags)

    sectionCard(title: String(localized: "Genres Distribution")) {
      if payload.genreDistribution.isEmpty {
        sectionEmptyState(systemImage: "chart.pie", message: String(localized: "No data"))
      } else {
        pieChart(payload.genreDistribution)
      }
    }

    sectionCard(title: String(localized: "Tags Distribution")) {
      if payload.tagDistribution.isEmpty {
        sectionEmptyState(systemImage: "chart.pie", message: String(localized: "No data"))
      } else {
        pieChart(payload.tagDistribution)
      }
    }
  }

  private func summarySection(_ summary: ReadingStatsSummary) -> some View {
    var cards = [
      (String(localized: "Books Started"), formatCount(summary.booksStartedReading), "book"),
      (String(localized: "Books Completed"), formatCount(summary.booksCompletedReading), "checkmark.circle"),
      (String(localized: "Pages Read"), formatCount(summary.totalPagesRead), "doc.text"),
      (String(localized: "Reading Days"), formatCount(summary.readingDays), "calendar"),
    ]
    if let currentStreakDays = summary.currentStreakDays, currentStreakDays > 0 {
      cards.append((String(localized: "Current Streak"), formatCount(currentStreakDays), "flame"))
    }
    if let longestStreakDays = summary.longestStreakDays, longestStreakDays > 0 {
      cards.append((String(localized: "Longest Streak"), formatCount(longestStreakDays), "trophy"))
    }
    cards += [
      (String(localized: "Avg Pages / Book"), formatDecimal(summary.averagePagesPerBook), "chart.bar.xaxis"),
      (String(localized: "Total Books"), formatCount(summary.totalBooks), "books.vertical"),
      (String(localized: "Last Read"), formatLastRead(summary.lastReadAt), "clock.arrow.circlepath"),
    ]

    return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
      ForEach(cards.indices, id: \.self) { index in
        let card = cards[index]
        VStack(alignment: .leading, spacing: 8) {
          Label(card.0, systemImage: card.2)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(card.1)
            .font(.title3)
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
      }
    }
  }

  private func distributionChart(
    _ items: [ReadingStatsItem],
    keepOrder: Bool = false,
    sparseAxisLabels: Bool = false,
    color: Color
  ) -> some View {
    let chartItems: [ReadingStatsItem]
    if keepOrder {
      chartItems = items
    } else {
      chartItems = Array(items.sorted { $0.value > $1.value }.prefix(16))
    }

    if sparseAxisLabels {
      let indexedItems = Array(chartItems.enumerated())
      return AnyView(
        Chart(indexedItems, id: \.offset) { item in
          BarMark(
            x: .value("Index", item.offset),
            y: .value("Value", item.element.value)
          )
          .foregroundStyle(color.gradient)
        }
        .chartXAxis {
          AxisMarks(values: distributionAxisIndices(count: chartItems.count, keepOrder: keepOrder)) { value in
            if let index = value.as(Int.self), index >= 0, index < chartItems.count {
              AxisValueLabel(chartItems[index].name)
            }
          }
        }
        .frame(height: 220)
      )
    }

    return AnyView(
      Chart(chartItems) { item in
        BarMark(
          x: .value("Label", item.name),
          y: .value("Value", item.value)
        )
        .foregroundStyle(color.gradient)
      }
      .frame(height: 220)
    )
  }

  private func pieChart(_ items: [ReadingStatsItem]) -> some View {
    let topItems = Array(items.sorted { $0.value > $1.value }.prefix(12))

    return Chart(topItems, id: \.id) { item in
      SectorMark(
        angle: .value("Value", item.value),
        innerRadius: .ratio(0.58),
        angularInset: 1.5
      )
      .foregroundStyle(by: .value("Label", item.name))
    }
    .frame(height: 240)
  }

  private func topItemsSection(title: String, items: [ReadingStatsItem]) -> some View {
    sectionCard(title: title) {
      let sortedItems = items.sorted { $0.value > $1.value }
      if sortedItems.isEmpty {
        sectionEmptyState(systemImage: "list.bullet", message: String(localized: "No data"))
      } else {
        VStack(spacing: 8) {
          ForEach(sortedItems.prefix(10).indices, id: \.self) { index in
            let item = sortedItems[index]
            HStack(spacing: 8) {
              Text("\(index + 1).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

              Text(item.name)
                .lineLimit(1)

              Spacer()

              Text(formatDecimal(item.value))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)
      content()
    }
    .padding(12)
    .background(.thinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func sectionEmptyState(systemImage: String, message: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
      Text(message)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
  }

  private func formatCount(_ value: Double) -> String {
    Int(max(value.rounded(), 0)).formatted()
  }

  private func formatDecimal(_ value: Double) -> String {
    if abs(value.rounded() - value) < 0.01 {
      return Int(value.rounded()).formatted()
    }

    return String(format: "%.1f", value)
  }

  private func formatLastRead(_ rawValue: String?) -> String {
    guard let rawValue else {
      return String(localized: "No record")
    }

    guard let date = ReadingStatsViewModel.parseDate(rawValue) else {
      return rawValue
    }

    return date.formattedMediumDate
  }

  private func distributionAxisIndices(count: Int, keepOrder: Bool) -> [Int] {
    guard count > 0 else { return [] }
    if keepOrder == false {
      return Array(0..<count)
    }
    let desiredMarks = 8
    let step = max(1, Int(ceil(Double(count) / Double(desiredMarks))))
    var indices = Array(stride(from: 0, to: count, by: step))
    if indices.last != count - 1 {
      indices.append(count - 1)
    }
    return indices
  }

  private func reload(forceRefresh: Bool) async {
    await viewModel.load(
      instanceId: current.instanceId,
      libraryId: selectedLibraryId,
      forceRefresh: forceRefresh
    )
  }

  private func loadLocalContext() async {
    let instanceId = current.instanceId
    guard !instanceId.isEmpty else {
      if !libraries.isEmpty {
        libraries = []
      }
      if syncInfo != nil {
        syncInfo = nil
      }
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedLibraries = try await database.fetchSidebarLibraries(instanceId: instanceId)
      let loadedSyncInfo = try await database.fetchOfflineInstanceSyncInfo(instanceId: instanceId)
      if libraries != loadedLibraries {
        libraries = loadedLibraries
      }
      if syncInfo != loadedSyncInfo {
        syncInfo = loadedSyncInfo
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
