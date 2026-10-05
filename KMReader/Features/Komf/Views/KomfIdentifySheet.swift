//
// KomfIdentifySheet.swift
//
//

import SwiftUI

struct KomfIdentifySheet: View {
  @Environment(\.dismiss) private var dismiss

  @State private var searchText: String
  @State private var results: [KomfSearchResult] = []
  @State private var isSearching = false
  @State private var searchFailed = false
  @State private var pendingKey: String?

  let series: Series
  let book: Book?

  init(series: Series, book: Book? = nil) {
    self.series = series
    self.book = book
    let title = series.metadata.title.isEmpty ? series.name : series.metadata.title
    _searchText = State(initialValue: title)
  }

  private var providerLinks: [KomfProviderLink] {
    let seriesLinks = series.metadata.links ?? []
    // Oneshots carry their provider links on the single book when the series has none.
    let links =
      !seriesLinks.isEmpty || !series.oneshot
      ? seriesLinks
      : (book?.metadata.links ?? [])
    return KomfProviderLink.parseAll(links)
  }

  private var trimmedQuery: String {
    searchText.trimmingCharacters(in: .whitespaces)
  }

  var body: some View {
    SheetView(
      title: String(localized: "Identify with komf"), size: .large, applyFormStyle: true
    ) {
      Form {
        Section {
          TextField(
            String(localized: "Search komf providers…"), text: $searchText
          )
          .autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
        }

        if !providerLinks.isEmpty {
          providerLinksSection
        }

        resultsSection
      }
      .task(id: trimmedQuery) {
        guard !trimmedQuery.isEmpty else {
          results = []
          searchFailed = false
          isSearching = false
          return
        }
        // Debounce: a newer keystroke cancels this task before the sleep ends.
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        await search()
      }
    }
  }

  @ViewBuilder
  private var providerLinksSection: some View {
    Section {
      if providerLinks.count > 1, let first = providerLinks.first {
        providerLinkRow(
          key: first.id,
          icon: "square.stack.3d.up",
          title: String(localized: "Aggregate all providers"),
          caption: String(localized: "Combine \(providerLinks.count) provider links"),
          provider: first.provider,
          providerSeriesId: first.providerSeriesId
        )
      }
      ForEach(providerLinks) { link in
        providerLinkRow(
          key: link.id,
          icon: "link",
          title: link.displayName,
          caption: link.providerSeriesId,
          provider: link.provider,
          providerSeriesId: link.providerSeriesId
        )
      }
    } header: {
      Text("Provider Links")
    }
  }

  @ViewBuilder
  private func providerLinkRow(
    key: String,
    icon: String,
    title: String,
    caption: String,
    provider: String,
    providerSeriesId: String
  ) -> some View {
    Button {
      Task {
        await submit(provider: provider, providerSeriesId: providerSeriesId)
      }
    } label: {
      HStack {
        Label {
          VStack(alignment: .leading) {
            Text(title)
            Text(caption)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        } icon: {
          Image(systemName: icon)
        }
        Spacer()
        if pendingKey == key {
          ProgressView()
        }
      }
      .foregroundStyle(.primary)
    }
    .disabled(pendingKey != nil)
  }

  @ViewBuilder
  private var resultsSection: some View {
    Section {
      if isSearching && results.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity)
      } else if searchFailed {
        VStack(spacing: 8) {
          Text("Search failed")
            .foregroundStyle(.secondary)
          Button("Retry") {
            Task {
              await search()
            }
          }
        }
        .frame(maxWidth: .infinity)
      } else if !trimmedQuery.isEmpty && results.isEmpty && !isSearching {
        Text("No results")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      } else {
        ForEach(results) { result in
          resultRow(result)
        }
      }
    }
  }

  @ViewBuilder
  private func resultRow(_ result: KomfSearchResult) -> some View {
    Button {
      Task {
        await submit(provider: result.provider, providerSeriesId: result.resultId)
      }
    } label: {
      HStack(spacing: 12) {
        AsyncImage(url: result.imageUrl.flatMap { URL(string: $0) }) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          case .failure:
            Image(systemName: "exclamationmark.circle")
              .foregroundStyle(.secondary)
          default:
            Image(systemName: "book.closed")
              .foregroundStyle(.secondary)
          }
        }
        .frame(width: 40, height: 60)
        .clipped()
        .cornerRadius(4)

        VStack(alignment: .leading, spacing: 2) {
          Text(result.title)
            .lineLimit(1)
          if !result.metaText.isEmpty {
            Text(result.metaText)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        Spacer()

        if pendingKey == result.id {
          ProgressView()
        } else {
          Text(result.provider)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(10)
        }
      }
      .foregroundStyle(.primary)
    }
    .disabled(pendingKey != nil)
  }

  private func search() async {
    isSearching = true
    searchFailed = false
    do {
      let fetched = try await KomfService.search(
        name: trimmedQuery,
        libraryId: series.libraryId,
        seriesId: series.id
      )
      // A superseded task must not clobber the newer query's state.
      if Task.isCancelled { return }
      results = fetched
    } catch {
      if Task.isCancelled { return }
      searchFailed = true
      results = []
    }
    isSearching = false
  }

  private func submit(provider: String, providerSeriesId: String) async {
    let key = "\(provider):\(providerSeriesId)"
    pendingKey = key
    do {
      let response = try await KomfService.identify(
        libraryId: series.libraryId,
        seriesId: series.id,
        provider: provider,
        providerSeriesId: providerSeriesId
      )
      KomfJobTracker.shared.track(
        jobId: response.id,
        seriesId: series.id,
        seriesTitle: series.metadata.title.isEmpty ? series.name : series.metadata.title
      )
      dismiss()
    } catch {
      await KomfIntegrationStore.shared.handleConflictIfNeeded(error)
      ErrorManager.shared.alert(error: error)
      pendingKey = nil
    }
  }
}
