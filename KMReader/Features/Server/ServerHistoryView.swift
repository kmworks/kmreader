//
// ServerHistoryView.swift
//
//

import SwiftUI

struct ServerHistoryView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var pagination = PaginationState<HistoricalEvent>(pageSize: 20)
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var lastTriggeredItemId: String?

  @State private var isClearingLocal = false

  @State private var bookNameById: [String: String] = [:]
  @State private var seriesNameById: [String: String] = [:]
  @State private var selectedEvent: HistoricalEvent?
  @State private var typeFilter: HistoricalEventType?
  @State private var filterLoadHalted = false

  private var displayedItems: [HistoricalEvent] {
    guard let typeFilter else { return pagination.items }
    return pagination.items.filter { $0.type == typeFilter.rawValue }
  }

  #if os(tvOS)
    private var filterMenuTitle: String {
      typeFilter?.label ?? String(localized: "history.allTypes", defaultValue: "All Types")
    }
  #endif

  var body: some View {
    List {
      if !current.isAdmin {
        AdminRequiredView()
      } else if isLoading && pagination.isEmpty {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else if pagination.isEmpty {
        Section {
          HStack {
            Spacer()
            VStack(spacing: 8) {
              Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
              Text(String(localized: "No history found"))
                .foregroundColor(.secondary)
            }
            Spacer()
          }
          .padding(.vertical)
          .tvFocusableHighlight()
        }
      } else {
        #if os(tvOS)
          if current.isAdmin {
            Section {
              Menu {
                filterMenuItems
              } label: {
                HStack {
                  Spacer()
                  Label(filterMenuTitle, systemImage: "line.3.horizontal.decrease.circle")
                  Spacer()
                }
              }

              Button(role: .destructive) {
                Task {
                  await clearLocalReferencedEntities()
                }
              } label: {
                HStack {
                  Spacer()
                  if isClearingLocal {
                    ProgressView()
                  } else {
                    Label(String(localized: "Clear Local Entries"), systemImage: "trash")
                  }
                  Spacer()
                }
              }
              .adaptiveButtonStyle(.borderedProminent)
              .disabled(isClearingLocal)
            }
            .listRowBackground(Color.clear)
          }
        #endif

        Section {
          ForEach(displayedItems, id: \.id) { event in
            historyRow(event: event)
          }

          if isLoadingMore {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
            .padding(.vertical)
          } else if typeFilter != nil && pagination.hasMorePages {
            if filterLoadHalted {
              HStack {
                Spacer()
                Button(String(localized: "Retry")) {
                  filterLoadHalted = false
                  Task {
                    await loadMoreHistory()
                  }
                }
                Spacer()
              }
              .padding(.vertical, 4)
            } else if displayedItems.isEmpty {
              HStack(spacing: 8) {
                Spacer()
                ProgressView()
                Text(
                  String(
                    localized: "history.lookingForEvents",
                    defaultValue: "Loading more to find matching events…")
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
              }
              .padding(.vertical)
              .onAppear {
                Task {
                  await loadMoreHistory()
                }
              }
            } else {
              HStack {
                Spacer()
                Button(String(localized: "Load More")) {
                  Task {
                    await loadMoreHistory()
                  }
                }
                Spacer()
              }
              .padding(.vertical, 4)
            }
          } else if typeFilter != nil && displayedItems.isEmpty {
            HStack {
              Spacer()
              Text(String(localized: "history.noMatchingEvents", defaultValue: "No matching events"))
                .foregroundColor(.secondary)
              Spacer()
            }
            .padding(.vertical)
          }
        }
      }
    }
    .optimizedListStyle()
    .platformNavigationTitle(ServerSection.history.title)
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            filterMenuItems
          } label: {
            Image(
              systemName: typeFilter == nil
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill"
            )
          }
          .disabled(!current.isAdmin)
          .help(String(localized: "history.filter", defaultValue: "Filter by Type"))
          .accessibilityLabel(String(localized: "history.filter", defaultValue: "Filter by Type"))
        }
        ToolbarItem(placement: .primaryAction) {
          Button(role: .destructive) {
            Task {
              await clearLocalReferencedEntities()
            }
          } label: {
            Label(String(localized: "Clear Local Entries"), systemImage: "trash")
          }
          .disabled(isClearingLocal || !current.isAdmin)
        }
      }
    #endif
    .sheet(item: $selectedEvent) { event in
      SheetView(title: String(localized: "History Details"), size: .large, applyFormStyle: true) {
        HistoryEventDetailView(event: event)
      }
    }
    .task {
      if current.isAdmin {
        await loadHistory(refresh: true)
      }
    }
    .refreshable {
      if current.isAdmin {
        await loadHistory(refresh: true)
      }
    }
    .onChange(of: typeFilter) { _, _ in
      filterLoadHalted = false
    }
  }

  @ViewBuilder
  private var filterMenuItems: some View {
    Picker(selection: $typeFilter) {
      Text(String(localized: "history.allTypes", defaultValue: "All Types"))
        .tag(HistoricalEventType?.none)
      ForEach(HistoricalEventType.allCases, id: \.self) { type in
        Text(type.label)
          .tag(HistoricalEventType?.some(type))
      }
    } label: {
      EmptyView()
    }
    .pickerStyle(.inline)
    .labelsHidden()
  }

  @ViewBuilder
  private func historyRow(event: HistoricalEvent) -> some View {
    Group {
      if let destination = navDestination(for: event) {
        NavigationLink(value: destination) {
          historyRowContent(event: event)
        }
      } else {
        historyRowContent(event: event)
          .tvFocusableHighlight()
      }
    }
    .contextMenu {
      detailsButton(for: event)
    }
    .onAppear {
      triggerLoadMoreIfNeeded(after: event)
    }
  }

  @ViewBuilder
  private func historyRowContent(event: HistoricalEvent) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        eventTypeBadge(for: event.type)

        Spacer()

        Text(relativeTimestamp(event.timestamp))
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }

      Text(primaryName(for: event))
        .lineLimit(1)
        .truncationMode(.tail)

      if let seriesId = event.seriesId, !seriesId.isEmpty, let seriesName = seriesNameById[seriesId] {
        HStack(spacing: 6) {
          Image(systemName: ContentIcon.series)
            .font(.caption)
          Text(seriesName)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }

      if let bookId = event.bookId, !bookId.isEmpty, let bookName = bookNameById[bookId] {
        HStack(spacing: 6) {
          Image(systemName: ContentIcon.book)
            .font(.caption)
          Text(bookName)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }

      if let extraLine = extraPropertiesLine(for: event) {
        Text(extraLine)
          .font(.caption2)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func eventTypeBadge(for type: String) -> some View {
    let eventType = HistoricalEventType(rawValue: type)
    Text(eventType?.label ?? type)
      .font(.caption2)
      .fontWeight(.medium)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background((eventType?.color ?? .gray).opacity(0.15), in: Capsule())
      .foregroundColor(eventType?.color ?? .gray)
  }

  @ViewBuilder
  private func detailsButton(for event: HistoricalEvent) -> some View {
    Button {
      selectedEvent = event
    } label: {
      Label(
        String(localized: "history.viewDetails", defaultValue: "View Details"),
        systemImage: "info.circle"
      )
    }
    .disabled(event.properties.isEmpty)
  }

  private func navDestination(for event: HistoricalEvent) -> NavDestination? {
    switch event.type {
    case HistoricalEventType.seriesFolderDeleted.rawValue:
      return nil
    case HistoricalEventType.bookFileDeleted.rawValue:
      guard let seriesId = event.seriesId, !seriesId.isEmpty else { return nil }
      return .seriesDetail(seriesId: seriesId)
    default:
      if let bookId = event.bookId, !bookId.isEmpty {
        return .bookDetail(bookId: bookId)
      }
      if let seriesId = event.seriesId, !seriesId.isEmpty {
        return .seriesDetail(seriesId: seriesId)
      }
      return nil
    }
  }

  private func primaryName(for event: HistoricalEvent) -> String {
    if let name = event.properties["name"], !name.isEmpty {
      return baseName(name)
    }
    if let bookId = event.bookId, let name = bookNameById[bookId] {
      return name
    }
    if let seriesId = event.seriesId, let name = seriesNameById[seriesId] {
      return name
    }
    return String(localized: "history.noFile", defaultValue: "No file")
  }

  private func baseName(_ path: String) -> String {
    path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
  }

  private func extraPropertiesLine(for event: HistoricalEvent) -> String? {
    let parts = event.properties
      .filter { $0.key != "name" }
      .sorted { $0.key < $1.key }
      .map { key, value in
        let displayValue: String
        if key.lowercased().contains("hash"), value.count > 12 {
          displayValue = String(value.prefix(12)) + "…"
        } else if key == "former file" || key == "source" {
          displayValue = baseName(value)
        } else {
          displayValue = value
        }
        return "\(key): \(displayValue)"
      }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private func relativeTimestamp(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func triggerLoadMoreIfNeeded(after event: HistoricalEvent) {
    guard pagination.hasMorePages,
      !isLoadingMore,
      pagination.shouldLoadMore(after: event, threshold: 3),
      lastTriggeredItemId != event.id
    else {
      return
    }
    lastTriggeredItemId = event.id
    Task {
      await loadMoreHistory()
    }
  }

  private func loadHistory(refresh: Bool) async {
    if refresh {
      withAnimation {
        pagination.reset()
      }
      lastTriggeredItemId = nil
      bookNameById.removeAll()
      seriesNameById.removeAll()
      filterLoadHalted = false
    }

    withAnimation {
      isLoading = true
    }

    do {
      let page = try await HistoryService.getHistory(
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      let items = page.content ?? []
      withAnimation {
        _ = pagination.applyPage(items)
        pagination.advance(moreAvailable: !(page.last ?? true))
      }
      lastTriggeredItemId = nil
      await updateLocalReferences(for: pagination.items)
    } catch {
      lastTriggeredItemId = nil
      ErrorManager.shared.alert(error: error)
    }

    withAnimation {
      isLoading = false
    }
  }

  private func loadMoreHistory() async {
    guard pagination.hasMorePages && !isLoadingMore else { return }

    withAnimation {
      isLoadingMore = true
    }

    do {
      let page = try await HistoryService.getHistory(
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      let items = page.content ?? []
      withAnimation {
        _ = pagination.applyPage(items)
        pagination.advance(moreAvailable: !(page.last ?? true))
      }
      lastTriggeredItemId = nil
      await updateLocalReferences(for: pagination.items)
    } catch {
      lastTriggeredItemId = nil
      filterLoadHalted = true
      ErrorManager.shared.alert(error: error)
    }

    withAnimation {
      isLoadingMore = false
    }
  }

  private func updateLocalReferences(for events: [HistoricalEvent]) async {
    let instanceId = AppConfig.current.instanceId
    let bookIds = Set(
      events
        .compactMap { $0.bookId }
        .filter { !$0.isEmpty }
    )
    let seriesIds = Set(
      events
        .compactMap { $0.seriesId }
        .filter { !$0.isEmpty }
    )

    let missingBookIds = bookIds.subtracting(bookNameById.keys)
    let missingSeriesIds = seriesIds.subtracting(seriesNameById.keys)
    guard !missingBookIds.isEmpty || !missingSeriesIds.isEmpty else {
      return
    }

    do {
      let references = try await DatabaseOperator.database().fetchHistoricalEventLocalReferences(
        instanceId: instanceId,
        bookIds: missingBookIds,
        seriesIds: missingSeriesIds
      )
      for (bookId, name) in references.bookNameById {
        bookNameById[bookId] = name
      }
      for (seriesId, name) in references.seriesNameById {
        seriesNameById[seriesId] = name
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func clearLocalReferencedEntities() async {
    guard !isClearingLocal else { return }
    isClearingLocal = true

    let instanceId = AppConfig.current.instanceId
    let bookIds = Set(
      pagination.items
        .filter { $0.type == HistoricalEventType.bookFileDeleted.rawValue }
        .compactMap { $0.bookId }
        .filter { !$0.isEmpty }
    )
    let seriesIds = Set(
      pagination.items
        .filter { $0.type == HistoricalEventType.seriesFolderDeleted.rawValue }
        .compactMap { $0.seriesId }
        .filter { !$0.isEmpty }
    )

    guard let database = await DatabaseOperator.databaseIfConfigured() else {
      ErrorManager.shared.alert(
        error: AppErrorType.storageNotConfigured(message: "DatabaseOperator has not been configured")
      )
      isClearingLocal = false
      return
    }

    for bookId in bookIds {
      await database.deleteBook(id: bookId, instanceId: instanceId)
    }
    for seriesId in seriesIds {
      await database.deleteSeries(id: seriesId, instanceId: instanceId)
    }

    for bookId in bookIds {
      bookNameById.removeValue(forKey: bookId)
    }
    for seriesId in seriesIds {
      seriesNameById.removeValue(forKey: seriesId)
    }

    await updateLocalReferences(for: pagination.items)

    let removedBooks = bookIds.count
    let removedSeries = seriesIds.count
    let removedTotal = removedBooks + removedSeries
    let message: String
    if removedTotal > 0 {
      message = String(localized: "notification.history.clearedLocalEntries")
    } else {
      message = String(localized: "notification.history.noLocalEntries")
    }
    ErrorManager.shared.notify(message: message)

    isClearingLocal = false
  }
}

private struct HistoryEventDetailView: View {
  let event: HistoricalEvent

  var body: some View {
    Form {
      Section {
        LabeledContent("Type", value: event.type)
        LabeledContent("Timestamp", value: event.timestamp.formattedMediumDateTime)
        if let seriesId = event.seriesId, !seriesId.isEmpty {
          LabeledContent("Series ID", value: seriesId)
        }
        if let bookId = event.bookId, !bookId.isEmpty {
          LabeledContent("Book ID", value: bookId)
        }
      }

      Section("Details") {
        if event.properties.isEmpty {
          Text("No details available")
            .foregroundColor(.secondary)
        } else {
          ForEach(event.properties.keys.sorted(), id: \.self) { key in
            LabeledContent(key, value: event.properties[key] ?? "")
          }
        }
      }
    }
  }
}
