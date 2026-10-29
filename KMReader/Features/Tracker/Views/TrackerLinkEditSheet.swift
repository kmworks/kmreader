//
// TrackerLinkEditSheet.swift
//

import Flow
import SwiftUI

struct TrackerLinkEditSheet: View {
  let seriesId: String
  let seriesTitle: String
  let alternateTitles: [String]
  let seriesLinks: [WebLink]
  let link: TrackerLink
  let onSaved: () async -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var selectedItem: TrackerSearchItem?
  @State private var searchResults: [TrackerSearchItem] = []
  @State private var suggestedResult: TrackerSearchItem?
  @State private var query: String
  @State private var searchTask: Task<Void, Never>?
  @State private var remoteLoadTask: Task<Void, Never>?
  @State private var isSearching = false
  @State private var mode: TrackerMode
  @State private var chapterOffset: Int
  @State private var remoteState: TrackerRemoteState?
  @State private var status: TrackerStatus?
  @State private var score = ""
  @State private var chapter = ""
  @State private var volume = ""
  @State private var startDate = ""
  @State private var finishDate = ""
  @State private var isSaving = false
  @State private var showDeleteConfirmation = false

  init(
    seriesId: String,
    seriesTitle: String,
    alternateTitles: [String],
    seriesLinks: [WebLink],
    link: TrackerLink,
    onSaved: @escaping () async -> Void
  ) {
    self.seriesId = seriesId
    self.seriesTitle = seriesTitle
    self.alternateTitles = alternateTitles
    self.seriesLinks = seriesLinks
    self.link = link
    self.onSaved = onSaved
    _query = State(initialValue: link.title ?? seriesTitle)
    _mode = State(initialValue: link.trackMode)
    _chapterOffset = State(initialValue: link.chapterOffset)
    _selectedItem = State(
      initialValue: link.trackId.isEmpty
        ? nil
        : TrackerSearchItem(id: link.trackId, title: link.title ?? link.trackId)
    )
  }

  private var searchTitles: [String] {
    var titles: [String] = []
    for title in [seriesTitle] + alternateTitles {
      let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
      if !title.isEmpty, !titles.contains(title) {
        titles.append(title)
      }
    }
    return titles
  }

  private var suggestedURL: URL? {
    TrackerProvider.entryURLs(in: seriesLinks)[link.provider]
  }

  private var visibleResults: [TrackerSearchItem] {
    guard let suggestedResult else { return searchResults }
    return searchResults.filter { $0.id != suggestedResult.id }
  }

  var body: some View {
    SheetView(
      title: link.provider.displayName,
      size: .large,
      applyFormStyle: true
    ) {
      Form {
        if let selectedItem {
          Section(header: Text(String(localized: "Tracker Entry"))) {
            TrackerSearchResultRow(result: selectedItem)
            HStack {
              Text(verbatim: "#\(selectedItem.id)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
              Spacer()
              if let url = selectedItem.remoteURL ?? link.provider.entryURL(trackId: selectedItem.id) {
                Link(destination: url) {
                  Label(String(localized: "Open"), systemImage: "arrow.up.right.square")
                    .font(.caption)
                }
                .buttonStyle(.borderless)
              }
              Button(String(localized: "Change")) {
                self.selectedItem = nil
                remoteState = nil
              }
              .font(.caption)
              .buttonStyle(.borderless)
            }
          }
        } else {
          Section(header: Text(String(localized: "Tracker Entry"))) {
            TextField(String(localized: "Search Title or URL"), text: $query)
              .onChange(of: query) { _, _ in scheduleSearch() }
            if searchTitles.count > 1 {
              HFlow(itemSpacing: 8) {
                ForEach(searchTitles, id: \.self) { title in
                  Button {
                    query = title
                    scheduleSearch()
                  } label: {
                    Text(title)
                      .font(.caption)
                      .lineLimit(1)
                      .padding(.horizontal, 10)
                      .padding(.vertical, 6)
                      .background(
                        query == title ? Color.accentColor.opacity(0.15) : LayoutConfig.neutralFillColor,
                        in: Capsule()
                      )
                      .overlay {
                        Capsule()
                          .strokeBorder(
                            query == title ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2)
                          )
                      }
                      .contentShape(Capsule())
                  }
                  .adaptiveButtonStyle(.plain)
                }
              }
            }
          }

          if let suggestedResult {
            Section(header: Text(String(localized: "From Series Links"))) {
              resultButton(suggestedResult)
            }
          }

          if isSearching || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section(header: Text(String(localized: "Search Results"))) {
              if isSearching {
                HStack {
                  Spacer()
                  ProgressView()
                  Spacer()
                }
              } else if visibleResults.isEmpty {
                Text(String(localized: "No results"))
                  .foregroundStyle(.secondary)
              }
              ForEach(visibleResults) { result in
                resultButton(result)
              }
            }
          }
        }

        if selectedItem != nil {
          Section(header: Text(String(localized: "Progress Mapping"))) {
            Picker(String(localized: "Mode"), selection: $mode) {
              ForEach(TrackerMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
              }
            }
            #if os(tvOS)
              TextField(
                String(localized: "Chapter Offset"),
                value: $chapterOffset,
                format: .number
              )
            #else
              Stepper(String(localized: "Chapter Offset"), value: $chapterOffset, in: -10000...10000)
            #endif
          }

          if remoteState != nil {
            Section {
              Picker(String(localized: "Status"), selection: $status) {
                Text(String(localized: "Unchanged")).tag(TrackerStatus?.none)
                ForEach(TrackerStatus.allCases, id: \.self) { status in
                  Text(status.displayName).tag(TrackerStatus?.some(status))
                }
              }
              TextField(String(localized: "Score"), text: $score)
              TextField(String(localized: "Chapter"), text: $chapter)
              TextField(String(localized: "Volume"), text: $volume)
              TextField(String(localized: "Start Date (YYYY-MM-DD)"), text: $startDate)
              TextField(String(localized: "Finish Date (YYYY-MM-DD)"), text: $finishDate)
            } header: {
              Text(String(localized: "Remote Progress"))
            } footer: {
              Text(
                String(
                  localized:
                    "Only changed, nonempty fields are submitted. Automatic sync still follows the series' completed books."
                ))
            }
          }
        }
      }
      .disabled(isSaving)
    } controls: {
      if link.trackId.isEmpty == false {
        Button(String(localized: "Unlink"), role: .destructive) {
          showDeleteConfirmation = true
        }
        .disabled(isSaving)
      }
      Button(String(localized: "Save")) { save() }
        .disabled(selectedItem == nil || isSaving)
    }
    .task(id: selectedItem?.id) {
      remoteLoadTask?.cancel()
      remoteLoadTask = Task {
        await loadRemoteState()
      }
      if selectedItem == nil, link.trackId.isEmpty {
        scheduleSearch()
      }
    }
    .task {
      await loadSuggestion()
    }
    .onDisappear {
      searchTask?.cancel()
      remoteLoadTask?.cancel()
    }
    .alert(String(localized: "Unlink Tracker"), isPresented: $showDeleteConfirmation) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Unlink"), role: .destructive) { unlink() }
    } message: {
      Text(String(localized: "This removes the series binding but does not change the remote entry."))
    }
  }

  private func resultButton(_ result: TrackerSearchItem) -> some View {
    Button {
      select(result)
    } label: {
      TrackerSearchResultRow(result: result)
        .contentShape(Rectangle())
    }
    .adaptiveButtonStyle(.plain)
  }

  private func loadSuggestion() async {
    guard let suggestedURL else { return }
    do {
      let results = try await TrackerService.search(provider: link.provider, name: suggestedURL.absoluteString)
      guard !Task.isCancelled else { return }
      suggestedResult = results.first
    } catch {}
  }

  private func scheduleSearch() {
    searchTask?.cancel()
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      searchResults = []
      isSearching = false
      return
    }
    isSearching = true
    searchTask = Task {
      try? await Task.sleep(nanoseconds: 300_000_000)
      guard !Task.isCancelled else { return }
      defer {
        if !Task.isCancelled { isSearching = false }
      }
      do {
        let results = try await TrackerService.search(provider: link.provider, name: text)
        guard !Task.isCancelled else { return }
        searchResults = results
      } catch {
        if !Task.isCancelled {
          ErrorManager.shared.alert(error: error)
        }
      }
    }
  }

  private func select(_ result: TrackerSearchItem) {
    selectedItem = result
    searchResults = []
    query = result.title
  }

  private func loadRemoteState() async {
    guard let selectedItem else { return }
    do {
      let state = try await TrackerService.getState(
        provider: link.provider, trackId: selectedItem.id)
      guard !Task.isCancelled, self.selectedItem?.id == selectedItem.id else { return }
      remoteState = state
      status = state.status
      score = state.score.map(String.init) ?? ""
      chapter =
        state.lastReadChapter.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) } ?? ""
      volume = state.lastReadVolume.map(String.init) ?? ""
      startDate = state.startReadDate ?? ""
      finishDate = state.finishReadDate ?? ""
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func save() {
    guard let selectedItem, !isSaving else { return }
    isSaving = true
    Task {
      do {
        _ = try await TrackerService.upsertLink(
          seriesId: seriesId,
          provider: link.provider,
          trackId: selectedItem.id,
          title: selectedItem.title,
          mode: mode,
          chapterOffset: chapterOffset
        )
        let remoteChanges = changedRemoteFields()
        if remoteState != nil, !remoteChanges.isEmpty {
          try await TrackerService.updateState(
            provider: link.provider,
            trackId: selectedItem.id,
            state: remoteChanges
          )
        }
        await onSaved()
        ErrorManager.shared.notify(message: String(localized: "Tracker link saved."))
        dismiss()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isSaving = false
    }
  }

  private func changedRemoteFields() -> [String: Any] {
    var fields: [String: Any] = [:]
    if let status, status != remoteState?.status {
      fields["status"] = status.rawValue
    }
    if let score = Int(score), score != remoteState?.score {
      fields["score"] = score
    }
    if let chapter = Double(chapter), chapter != remoteState?.lastReadChapter {
      fields["lastReadChapter"] = chapter
    }
    if let volume = Int(volume), volume != remoteState?.lastReadVolume {
      fields["lastReadVolume"] = volume
    }
    if !startDate.isEmpty, startDate != remoteState?.startReadDate {
      fields["startReadDate"] = startDate
    }
    if !finishDate.isEmpty, finishDate != remoteState?.finishReadDate {
      fields["finishReadDate"] = finishDate
    }
    return fields
  }

  private func unlink() {
    isSaving = true
    Task {
      do {
        try await TrackerService.deleteLink(seriesId: seriesId, provider: link.provider)
        await onSaved()
        ErrorManager.shared.notify(message: String(localized: "Tracker unlinked."))
        dismiss()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isSaving = false
    }
  }
}
