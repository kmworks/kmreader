//
// SettingsLogsView.swift
//
//

import Flow
import SwiftUI

struct SettingsLogsView: View {
  @State private var pagination = PaginationState<LogStore.LogEntry>(pageSize: 50)
  @State private var categoryCounts: [LogStore.CategoryCount] = []
  @State private var isLoading = false
  @State private var selectedLevel: LogLevel = .info
  @State private var selectedCategory: String = "All"
  @State private var searchText = ""
  @State private var isLoadingMore = false
  @State private var queryGeneration = 0
  @State private var activeQueryKey: LogQueryKey?
  @State private var lastTriggeredEntryId: Int64?

  private var selectedLevelBinding: Binding<LogLevel> {
    Binding(
      get: { selectedLevel },
      set: { setSelectedLevel($0) }
    )
  }

  private var currentQueryKey: LogQueryKey {
    LogQueryKey(
      minPriority: selectedLevel.priority,
      category: selectedCategory == "All" ? nil : selectedCategory,
      search: searchText.isEmpty ? nil : searchText
    )
  }

  private var totalCount: Int {
    categoryCounts.reduce(0) { $0 + $1.count }
  }

  var body: some View {
    List {
      Section {
        if isLoading && pagination.isEmpty {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        } else if pagination.isEmpty {
          Text(String(localized: "settings.logs.empty"))
            .foregroundColor(.secondary)
        } else {
          ForEach(pagination.items) { entry in
            logEntryRow(entry)
          }

          if isLoadingMore {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
          }
        }
      } header: {
        filterControls
      }
    }
    .optimizedListStyle(alternatesRowBackgrounds: true)
    #if os(iOS)
      .searchable(text: $searchText, prompt: String(localized: "settings.logs.search"))
    #endif
    .onSubmit(of: .search) {
      Task { await loadLogs() }
    }
    .onChange(of: selectedLevel) {
      Task { await loadLogs() }
    }
    .onChange(of: selectedCategory) {
      Task { await loadLogs() }
    }
    .refreshable {
      await loadLogs()
    }
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            ShareLink(item: exportLogs()) {
              Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
              Task {
                await clearLogs()
              }
            } label: {
              Label(String(localized: "Clear All"), systemImage: "trash")
            }
          } label: {
            Image(systemName: "ellipsis")
          }
        }
      }
    #endif
    .task {
      await loadLogs()
    }
    .platformNavigationTitle(SettingsSection.logs.title)
  }

  @ViewBuilder
  private var filterControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      #if os(macOS)
        TextField(String(localized: "settings.logs.search"), text: $searchText)
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            Task { await loadLogs() }
          }
      #endif

      HFlow(spacing: 8) {
        Menu {
          Picker("Level", selection: selectedLevelBinding) {
            ForEach(LogLevel.allCases, id: \.self) { level in
              Text(level.rawValue).tag(level)
            }
          }
          .pickerStyle(.inline)
        } label: {
          LogFilterChip(icon: "flag", text: selectedLevel.rawValue, color: selectedLevel.color)
        }

        CategoryChip(
          name: "All",
          count: totalCount,
          isSelected: selectedCategory == "All"
        ) {
          setSelectedCategory("All")
        }

        ForEach(categoryCounts, id: \.category) { category in
          CategoryChip(
            name: category.category,
            count: category.count,
            isSelected: selectedCategory == category.category
          ) {
            setSelectedCategory(category.category)
          }
        }
      }
      .adaptiveButtonStyle(.bordered)
    }
  }

  @ViewBuilder
  private func logEntryRow(_ entry: LogStore.LogEntry) -> some View {
    LogEntryRow(entry: entry)
      .tvFocusableHighlight()
      .onAppear {
        guard pagination.hasMorePages,
          !isLoading,
          !isLoadingMore,
          pagination.shouldLoadMore(after: entry, threshold: 3),
          lastTriggeredEntryId != entry.id
        else {
          return
        }

        lastTriggeredEntryId = entry.id
        Task {
          await loadMoreLogs()
        }
      }
      #if os(iOS) || os(macOS)
        .contextMenu {
          Button {
            copyToClipboard(formatEntry(entry))
          } label: {
            Label(String(localized: "Copy"), systemImage: "doc.on.doc")
          }
        }
      #endif
  }

  private func loadLogs() async {
    queryGeneration += 1
    let generation = queryGeneration
    let queryKey = currentQueryKey
    prepareForLogReload(queryKey: queryKey)

    let counts = await LogStore.shared.categoryCounts(
      minPriority: queryKey.minPriority,
      search: queryKey.search
    )
    let entries = await LogStore.shared.query(
      minPriority: queryKey.minPriority,
      category: queryKey.category,
      search: queryKey.search,
      limit: pagination.pageSize
    )
    guard generation == queryGeneration, activeQueryKey == queryKey else { return }

    withAnimation {
      categoryCounts = counts
      _ = pagination.applyPage(entries)
      pagination.advance(moreAvailable: entries.count == pagination.pageSize)
      isLoading = false
    }
  }

  private func prepareForLogReload(queryKey: LogQueryKey) {
    let pageSize = pagination.pageSize
    lastTriggeredEntryId = nil
    activeQueryKey = queryKey

    withAnimation {
      pagination = PaginationState<LogStore.LogEntry>(pageSize: pageSize)
      isLoading = true
      isLoadingMore = false
    }
  }

  private func loadMoreLogs() async {
    guard pagination.hasMorePages && !isLoading && !isLoadingMore else { return }
    guard let lastEntry = pagination.items.last else { return }
    guard let queryKey = activeQueryKey else { return }
    withAnimation {
      isLoadingMore = true
    }

    let generation = queryGeneration
    let entries = await LogStore.shared.query(
      minPriority: queryKey.minPriority,
      category: queryKey.category,
      search: queryKey.search,
      before: LogStore.PageCursor(entry: lastEntry),
      limit: pagination.pageSize
    )
    guard generation == queryGeneration, activeQueryKey == queryKey else { return }

    withAnimation {
      _ = pagination.applyPage(entries)
      pagination.advance(moreAvailable: entries.count == pagination.pageSize)
      isLoadingMore = false
      lastTriggeredEntryId = nil
    }
  }

  private func setSelectedLevel(_ level: LogLevel) {
    guard selectedLevel != level else { return }
    withAnimation {
      selectedLevel = level
    }
  }

  private func setSelectedCategory(_ category: String) {
    guard selectedCategory != category else { return }
    withAnimation {
      selectedCategory = category
    }
  }

  private func exportLogs() -> String {
    pagination.items.map { formatEntry($0) }.joined(separator: "\n")
  }

  private func clearLogs() async {
    await LogStore.shared.clear()
    await loadLogs()
  }

  private func formatEntry(_ entry: LogStore.LogEntry) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let level = LogLevel(entry.level).rawValue
    return
      "[\(formatter.string(from: entry.date))] [\(level)] [\(entry.category)] \(entry.message)"
  }

  private func copyToClipboard(_ text: String) {
    #if os(iOS)
      UIPasteboard.general.string = text
    #elseif os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #endif
    ErrorManager.shared.notify(message: String(localized: "notification.copied"))
  }
}

private struct LogQueryKey: Hashable {
  let minPriority: Int
  let category: String?
  let search: String?
}

// MARK: - Log Filter Chip

struct LogFilterChip: View {
  let icon: String
  let text: String
  var color: Color = .secondary

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.caption)
      Text(text)
        .font(.footnote)
        .fontWeight(.medium)
    }
    .fixedSize()
    .tint(color)
  }
}

// MARK: - Category Chip

struct CategoryChip: View {
  let name: String
  let count: Int
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Text(name)
          .font(.footnote)
          .fontWeight(.medium)
        Text("\(count)")
          .font(.caption)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
          .clipShape(Capsule())
      }
      .fixedSize()
    }
    .adaptiveButtonStyle(isSelected ? .borderedProminent : .bordered)
  }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
  let entry: LogStore.LogEntry

  private var dateString: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter.string(from: entry.date)
  }

  var level: LogLevel {
    LogLevel(entry.level)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(level.rawValue)
          .font(.caption.bold())
          .foregroundColor(level.color)
        Text(entry.category)
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        Text(dateString)
          .font(.caption.monospaced())
          .foregroundColor(.secondary)
      }
      Text(entry.message)
        .font(.footnote.monospaced())
        .lineLimit(5)
        .textSelectionIfAvailable()
    }
    .padding(.vertical, 2)
  }
}
