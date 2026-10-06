//
// MetadataFilterSection.swift
//
//

import SwiftUI

struct MetadataFilterSection: View {
  @Binding var metadataFilter: MetadataFilterConfig
  let libraryIds: [String]?
  let collectionId: String?
  let seriesId: String?
  let readListId: String?
  let showPublisher: Bool
  let showAuthors: Bool
  let showGenres: Bool
  let showTags: Bool
  let showLanguages: Bool
  let showAgeRatings: Bool
  let showReleaseYears: Bool

  @State private var publishers: [String]?
  @State private var authors: [String]?
  @State private var genres: [String]?
  @State private var tags: [String]?
  @State private var languages: [String]?
  @State private var ageRatings: [String]?
  @State private var releaseYears: [String]?

  init(
    metadataFilter: Binding<MetadataFilterConfig>,
    libraryIds: [String]? = nil,
    collectionId: String? = nil,
    seriesId: String? = nil,
    readListId: String? = nil,
    showPublisher: Bool = false,
    showAuthors: Bool = false,
    showGenres: Bool = false,
    showTags: Bool = false,
    showLanguages: Bool = false,
    showAgeRatings: Bool = false,
    showReleaseYears: Bool = false
  ) {
    self._metadataFilter = metadataFilter
    self.libraryIds = libraryIds
    self.collectionId = collectionId
    self.seriesId = seriesId
    self.readListId = readListId
    self.showPublisher = showPublisher
    self.showAuthors = showAuthors
    self.showGenres = showGenres
    self.showTags = showTags
    self.showLanguages = showLanguages
    self.showAgeRatings = showAgeRatings
    self.showReleaseYears = showReleaseYears
  }

  var body: some View {
    if showPublisher || showAuthors || showGenres || showTags || showLanguages || showAgeRatings || showReleaseYears {
      Section(String(localized: "Metadata")) {
        if showPublisher {
          publisherPicker
        }

        if showAuthors {
          authorsSection
        }

        if showGenres {
          genresSection
        }

        if showTags {
          tagsSection
        }

        if showLanguages {
          languagesSection
        }

        if showAgeRatings {
          ageRatingsSection
        }

        if showReleaseYears {
          releaseYearsSection
        }
      }
    }
  }

  @ViewBuilder
  private var publisherPicker: some View {
    NavigationLink {
      MetadataMultiSelectLoader(
        title: String(localized: "Publishers"),
        cachedItems: $publishers,
        source: .publishers,
        selectedItems: Binding(
          get: { Set(metadataFilter.publishers ?? []) },
          set: { metadataFilter.publishers = $0.isEmpty ? nil : Array($0).localizedSorted() }
        ),
        logic: $metadataFilter.publishersLogic,
        emptyDescription: String(localized: "No publishers available")
      )
    } label: {
      HStack {
        Text(String(localized: "Publishers"))
        Spacer()
        if let publishers = metadataFilter.publishers, !publishers.isEmpty {
          let logicSymbol = metadataFilter.publishersLogic == .all ? "∧" : "∨"
          Text(publishers.joined(separator: " \(logicSymbol) "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  @ViewBuilder
  private var authorsSection: some View {
    NavigationLink {
      MetadataMultiSelectLoader(
        title: String(localized: "Authors"),
        cachedItems: $authors,
        source: .authors(
          seriesId: seriesId,
          libraryIds: libraryIds,
          collectionId: collectionId,
          readListId: readListId
        ),
        selectedItems: Binding(
          get: { Set(metadataFilter.authors ?? []) },
          set: { metadataFilter.authors = $0.isEmpty ? nil : Array($0).localizedSorted() }
        ),
        logic: $metadataFilter.authorsLogic,
        emptyDescription: String(localized: "No authors available")
      )
    } label: {
      HStack {
        Text(String(localized: "Authors"))
        Spacer()
        if let authors = metadataFilter.authors, !authors.isEmpty {
          let logicSymbol = metadataFilter.authorsLogic == .all ? "∧" : "∨"
          Text(authors.joined(separator: " \(logicSymbol) "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  @ViewBuilder
  private var genresSection: some View {
    NavigationLink {
      MetadataMultiSelectLoader(
        title: String(localized: "Genres"),
        cachedItems: $genres,
        source: .genres(libraryIds: libraryIds, collectionId: collectionId),
        selectedItems: Binding(
          get: { Set(metadataFilter.genres ?? []) },
          set: { metadataFilter.genres = $0.isEmpty ? nil : Array($0).localizedSorted() }
        ),
        logic: $metadataFilter.genresLogic,
        emptyDescription: String(localized: "No genres available")
      )
    } label: {
      HStack {
        Text(String(localized: "Genres"))
        Spacer()
        if let genres = metadataFilter.genres, !genres.isEmpty {
          let logicSymbol = metadataFilter.genresLogic == .all ? "∧" : "∨"
          Text(genres.joined(separator: " \(logicSymbol) "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  @ViewBuilder
  private var tagsSection: some View {
    NavigationLink {
      MetadataMultiSelectLoader(
        title: String(localized: "Tags"),
        cachedItems: $tags,
        source: .tags(
          seriesId: seriesId,
          readListId: readListId,
          libraryIds: libraryIds,
          collectionId: collectionId
        ),
        selectedItems: Binding(
          get: { Set(metadataFilter.tags ?? []) },
          set: { metadataFilter.tags = $0.isEmpty ? nil : Array($0).localizedSorted() }
        ),
        logic: $metadataFilter.tagsLogic,
        emptyDescription: String(localized: "No tags available")
      )
    } label: {
      HStack {
        Text(String(localized: "Tags"))
        Spacer()
        if let tags = metadataFilter.tags, !tags.isEmpty {
          let logicSymbol = metadataFilter.tagsLogic == .all ? "∧" : "∨"
          Text(tags.joined(separator: " \(logicSymbol) "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  @ViewBuilder
  private var languagesSection: some View {
    NavigationLink {
      MetadataMultiSelectLoader(
        title: String(localized: "Languages"),
        cachedItems: $languages,
        source: .languages(libraryIds: libraryIds, collectionId: collectionId),
        selectedItems: Binding(
          get: { Set(metadataFilter.languages ?? []) },
          set: { metadataFilter.languages = $0.isEmpty ? nil : Array($0).localizedSorted() }
        ),
        logic: $metadataFilter.languagesLogic,
        emptyDescription: String(localized: "No languages available"),
        displayStyle: .language
      )
    } label: {
      HStack {
        Text(String(localized: "Languages"))
        Spacer()
        if let languages = metadataFilter.languages, !languages.isEmpty {
          let logicSymbol = metadataFilter.languagesLogic == .all ? "∧" : "∨"
          let displayNames = languages.map { LanguageCodeHelper.displayName(for: $0) }
          Text(displayNames.joined(separator: " \(logicSymbol) "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }
  @ViewBuilder
  private var ageRatingsSection: some View {
    NavigationLink {
      MetadataMultiSelectLoader(
        title: String(localized: "Age Ratings"),
        cachedItems: $ageRatings,
        source: .ageRatings(libraryIds: libraryIds, collectionId: collectionId),
        selectedItems: Binding(
          get: { Set(metadataFilter.ageRatings ?? []) },
          set: { metadataFilter.ageRatings = $0.isEmpty ? nil : Array($0).localizedSorted() }
        ),
        logic: $metadataFilter.ageRatingsLogic,
        emptyDescription: String(localized: "No age ratings available"),
        displayStyle: .ageRating
      )
    } label: {
      HStack {
        Text(String(localized: "Age Ratings"))
        Spacer()
        if let ageRatings = metadataFilter.ageRatings, !ageRatings.isEmpty {
          let logicSymbol = metadataFilter.ageRatingsLogic == .all ? "∧" : "∨"
          Text(ageRatings.map { "\($0)+" }.joined(separator: " \(logicSymbol) "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  @ViewBuilder
  private var releaseYearsSection: some View {
    NavigationLink {
      MetadataMultiSelectLoader(
        title: String(localized: "Release Years"),
        cachedItems: $releaseYears,
        source: .releaseYears(libraryIds: libraryIds, collectionId: collectionId),
        selectedItems: Binding(
          get: { Set(metadataFilter.releaseYears ?? []) },
          set: { metadataFilter.releaseYears = $0.isEmpty ? nil : Array($0).localizedSorted() }
        ),
        logic: $metadataFilter.releaseYearsLogic,
        emptyDescription: String(localized: "No release years available")
      )
    } label: {
      HStack {
        Text(String(localized: "Release Years"))
        Spacer()
        if let releaseYears = metadataFilter.releaseYears, !releaseYears.isEmpty {
          let logicSymbol = metadataFilter.releaseYearsLogic == .all ? "∧" : "∨"
          Text(releaseYears.joined(separator: " \(logicSymbol) "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }
}

@MainActor
struct MetadataMultiSelectLoader: View {
  let title: String
  @Binding var cachedItems: [String]?
  let source: MetadataFilterItemSource
  @Binding var selectedItems: Set<String>
  @Binding var logic: FilterLogic
  let emptyDescription: String
  let displayStyle: MetadataFilterDisplayStyle

  @State private var isLoading = false
  @State private var loadError: Error?
  @Environment(\.dismiss) private var dismiss

  init(
    title: String,
    cachedItems: Binding<[String]?>,
    source: MetadataFilterItemSource,
    selectedItems: Binding<Set<String>>,
    logic: Binding<FilterLogic>,
    emptyDescription: String,
    displayStyle: MetadataFilterDisplayStyle = .plain
  ) {
    self.title = title
    self._cachedItems = cachedItems
    self.source = source
    self._selectedItems = selectedItems
    self._logic = logic
    self.emptyDescription = emptyDescription
    self.displayStyle = displayStyle
  }

  var body: some View {
    Group {
      if let items = cachedItems {
        if items.isEmpty {
          ContentUnavailableView(
            title,
            systemImage: AppIcon.filterCircle,
            description: Text(emptyDescription)
          )
          .toolbar { placeholderToolbar }
        } else {
          MultiSelectList(
            title: title,
            items: items,
            selectedItems: $selectedItems,
            logic: $logic,
            displayStyle: displayStyle
          )
        }
      } else if isLoading {
        ProgressView(String(localized: "Loading"))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .toolbar { placeholderToolbar }
      } else if let loadError {
        VStack(spacing: 16) {
          ContentUnavailableView(
            String(localized: "Unable to load filters"),
            systemImage: AppIcon.loadError,
            description: Text(loadError.localizedDescription)
          )
          Button(String(localized: "Retry")) {
            Task { await loadMetadata(force: true) }
          }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { placeholderToolbar }
      } else {
        ProgressView(String(localized: "Loading"))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .toolbar { placeholderToolbar }
      }
    }
    .task {
      await loadMetadata(force: false)
    }
  }

  private func loadMetadata(force: Bool) async {
    guard force || cachedItems == nil else { return }
    withAnimation {
      isLoading = true
      loadError = nil
    }
    do {
      let items = try await source.load()
      withAnimation {
        cachedItems = items.localizedSorted()
      }
    } catch {
      withAnimation {
        loadError = error
      }
    }
    withAnimation {
      isLoading = false
    }
  }

  @ToolbarContentBuilder
  private var placeholderToolbar: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button(String(localized: "Reset")) {
        selectedItems.removeAll()
      }
      .disabled(selectedItems.isEmpty)
    }
    ToolbarItem(placement: .confirmationAction) {
      Button(String(localized: "Done")) {
        dismiss()
      }
    }
  }
}

struct MultiSelectList: View {
  let title: String
  let items: [String]
  @Binding var selectedItems: Set<String>
  @Binding var logic: FilterLogic
  let displayStyle: MetadataFilterDisplayStyle
  @Environment(\.dismiss) private var dismiss
  @State private var searchText: String = ""

  init(
    title: String,
    items: [String],
    selectedItems: Binding<Set<String>>,
    logic: Binding<FilterLogic>,
    displayStyle: MetadataFilterDisplayStyle = .plain
  ) {
    self.title = title
    self.items = items
    self._selectedItems = selectedItems
    self._logic = logic
    self.displayStyle = displayStyle
  }

  private var filteredItems: [String] {
    if searchText.isEmpty {
      return items
    }
    return items.filter { item in
      displayStyle.displayName(for: item).localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    List {
      Section {
        Picker(String(localized: "Logic"), selection: $logic) {
          Text(String(localized: "All")).tag(FilterLogic.all)
          Text(String(localized: "Any")).tag(FilterLogic.any)
        }
        .pickerStyle(.segmented)
      }

      Section {
        ForEach(filteredItems, id: \.self) { item in
          SelectableRow(
            item: item,
            displayName: displayStyle.displayName(for: item),
            isSelected: selectedItems.contains(item)
          ) {
            toggleSelection(for: item)
          }
        }
      }
    }
    .searchable(text: $searchText, prompt: String(localized: "Search"))
    .platformNavigationTitle(title)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(String(localized: "Reset")) {
          withAnimation {
            selectedItems.removeAll()
          }
        }
        .disabled(selectedItems.isEmpty)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(String(localized: "Done")) {
          dismiss()
        }
      }
    }
  }

  private func toggleSelection(for item: String) {
    if selectedItems.contains(item) {
      selectedItems.remove(item)
    } else {
      selectedItems.insert(item)
    }
  }
}

struct SelectableRow: View {
  let item: String
  let displayName: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Text(displayName)
        Spacer()
        if isSelected {
          Image(systemName: AppIcon.confirm)
            .foregroundStyle(.green)
        }
      }
      .animation(.appCurve(), value: isSelected)
    }
  }
}
