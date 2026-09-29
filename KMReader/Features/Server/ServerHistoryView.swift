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
        #if os(tvOS) || os(macOS)
          if current.isAdmin {
            Section {
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
          ForEach(pagination.items, id: \.id) { event in
            historyRow(event: event)
          }

          if isLoadingMore {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
            .padding(.vertical)
          }
        }
      }
    }
    .optimizedListStyle()
    .platformNavigationTitle(ServerSection.history.title)
    #if os(iOS)
      .toolbar {
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
  }

  @ViewBuilder
  private func historyRow(event: HistoricalEvent) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: iconName(for: event.type))
        .foregroundColor(.secondary)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(event.type)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)

          Spacer()

          Text(event.timestamp.formattedMediumDateTime)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

          Button {
            selectedEvent = event
          } label: {
            Image(systemName: "info.circle")
          }
          .buttonStyle(.borderless)
          .disabled(event.properties.isEmpty)
          .frame(width: 24)
        }

        if let seriesId = event.seriesId, !seriesId.isEmpty {
          HStack(spacing: 6) {
            Image(systemName: ContentIcon.series)
              .font(.caption)
            Text(seriesNameById[seriesId] ?? seriesId)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
        }

        if let bookId = event.bookId, !bookId.isEmpty {
          HStack(spacing: 6) {
            Image(systemName: ContentIcon.book)
              .font(.caption)
            Text(bookNameById[bookId] ?? bookId)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .tvFocusableHighlight()
    .padding(.vertical, 4)
    .onAppear {
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
  }

  private func loadHistory(refresh: Bool) async {
    if refresh {
      withAnimation {
        pagination.reset()
      }
      lastTriggeredItemId = nil
      bookNameById.removeAll()
      seriesNameById.removeAll()
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
        .filter { $0.type == "BookFileDeleted" }
        .compactMap { $0.bookId }
        .filter { !$0.isEmpty }
    )
    let seriesIds = Set(
      events
        .filter { $0.type == "SeriesFolderDeleted" }
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
        .filter { $0.type == "BookFileDeleted" }
        .compactMap { $0.bookId }
        .filter { !$0.isEmpty }
    )
    let seriesIds = Set(
      pagination.items
        .filter { $0.type == "SeriesFolderDeleted" }
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

  private func iconName(for type: String) -> String {
    switch type {
    case "BookFileDeleted":
      return "xmark.circle"
    case "SeriesFolderDeleted":
      return "folder.badge.minus"
    case "DuplicatePageDeleted":
      return "book.closed"
    case "BookConverted":
      return "archivebox"
    case "BookImported":
      return "tray.and.arrow.down"
    default:
      return "clock"
    }
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
