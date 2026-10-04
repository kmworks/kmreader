//
// MediaAnalysisView.swift
//
//

import SwiftUI

struct MediaAnalysisView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var pagination = PaginationState<Book>(pageSize: 20)
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var lastTriggeredItemId: String?

  @State private var hasLoaded = false
  @State private var filterError = true
  @State private var filterUnsupported = true
  @State private var libraries: [LibraryInfo] = []
  @State private var selectedLibraryIds: Set<String> = []

  private var allLibrariesBinding: Binding<Bool> {
    Binding(
      get: { selectedLibraryIds.isEmpty },
      set: { newValue in
        if newValue {
          selectedLibraryIds.removeAll()
        }
      }
    )
  }

  private func libraryBinding(_ libraryId: String) -> Binding<Bool> {
    Binding(
      get: { selectedLibraryIds.contains(libraryId) },
      set: { isOn in
        if isOn {
          selectedLibraryIds.insert(libraryId)
        } else {
          selectedLibraryIds.remove(libraryId)
        }
      }
    )
  }

  var body: some View {
    List {
      if !current.isAdmin {
        AdminRequiredView()
      } else {
        filterSection
        librarySection
        contentSection
      }
    }
    .optimizedListStyle()
    .platformNavigationTitle(String(localized: "Media Analysis"))
    .task {
      if current.isAdmin && !hasLoaded {
        await loadLibraries()
        await loadData(refresh: true)
        hasLoaded = true
      }
    }
    .refreshable {
      if current.isAdmin {
        await loadData(refresh: true)
      }
    }
    .onChange(of: filterError) {
      Task { await loadData(refresh: true) }
    }
    .onChange(of: filterUnsupported) {
      Task { await loadData(refresh: true) }
    }
    .onChange(of: selectedLibraryIds) {
      Task { await loadData(refresh: true) }
    }
  }

  private var filterSection: some View {
    Section(String(localized: "Filters")) {
      Toggle(String(localized: "Error"), isOn: $filterError)
      Toggle(String(localized: "Unsupported"), isOn: $filterUnsupported)
    }
  }

  @ViewBuilder
  private var librarySection: some View {
    if !libraries.isEmpty {
      Section(String(localized: "Libraries")) {
        Toggle(
          String(localized: "All Libraries"),
          isOn: allLibrariesBinding
        )

        ForEach(libraries) { library in
          Toggle(
            library.name,
            isOn: libraryBinding(library.id)
          )
        }
      }
    }
  }

  @ViewBuilder
  private var contentSection: some View {
    if isLoading && pagination.isEmpty {
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
            Image(systemName: "checkmark.circle")
              .font(.system(size: 40))
              .foregroundColor(.green)
            Text(String(localized: "No issues found"))
              .foregroundColor(.secondary)
          }
          Spacer()
        }
        .padding(.vertical)
      }
    } else {
      Section {
        ForEach(pagination.items) { book in
          mediaAnalysisRow(book: book)
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

  @ViewBuilder
  private func mediaAnalysisRow(book: Book) -> some View {
    NavigationLink(value: NavDestination.bookDetail(bookId: book.id)) {
      HStack(spacing: 12) {
        ThumbnailImage(
          id: book.id,
          type: .book,
          shadowStyle: .none,
          width: 40,
          cornerRadius: 4,
          isTransitionSource: false
        )

        VStack(alignment: .leading, spacing: 4) {
          Text(book.name)
            .lineLimit(2)

          HStack(spacing: 8) {
            Label(
              book.media.statusValue.label,
              systemImage: book.media.statusValue.icon
            )
            .font(.caption)
            .foregroundColor(book.media.statusValue.color)

            if !book.media.mediaType.isEmpty {
              Text(book.media.mediaType)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Text(book.size)
              .font(.caption)
              .foregroundColor(.secondary)
          }

          if let comment = book.media.localizedComment {
            Text(comment)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(2)
          }

          if let libraryName = libraries.first(where: { $0.id == book.libraryId })?.name {
            Text(libraryName)
              .font(.caption2)
              .foregroundColor(.secondary)
          }

          if book.deleted {
            Text(String(localized: "Unavailable"))
              .font(.caption2)
              .fontWeight(.semibold)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.red.opacity(0.15), in: Capsule())
              .foregroundColor(.red)
          }
        }
      }
    }
    .onAppear {
      guard pagination.hasMorePages,
        !isLoadingMore,
        pagination.shouldLoadMore(after: book, threshold: 3),
        lastTriggeredItemId != book.id
      else { return }
      lastTriggeredItemId = book.id
      Task { await loadMore() }
    }
  }

  private var selectedStatuses: [MediaStatus] {
    var statuses: [MediaStatus] = []
    if filterError { statuses.append(.error) }
    if filterUnsupported { statuses.append(.unsupported) }
    return statuses
  }

  private func loadLibraries() async {
    let instanceId = AppConfig.current.instanceId
    guard !instanceId.isEmpty else { return }
    libraries =
      (await DatabaseOperator.databaseIfConfigured()?.fetchLibraries(instanceId: instanceId) ?? [])
      .filter { $0.id != KomgaLibrary.allLibrariesId }
  }

  private func loadData(refresh: Bool) async {
    let statuses = selectedStatuses
    guard !statuses.isEmpty else {
      withAnimation {
        pagination.reset()
        _ = pagination.applyPage([])
      }
      return
    }

    if refresh {
      withAnimation {
        pagination.reset()
      }
      lastTriggeredItemId = nil
    }

    let libraryIds = selectedLibraryIds.isEmpty ? nil : Array(selectedLibraryIds)

    withAnimation {
      isLoading = true
    }
    do {
      let page = try await MediaManagementService.getMediaAnalysisBooks(
        statuses: statuses,
        libraryIds: libraryIds,
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      withAnimation {
        _ = pagination.applyPage(page.content)
        pagination.advance(moreAvailable: !page.last)
      }
      lastTriggeredItemId = nil
    } catch {
      lastTriggeredItemId = nil
      ErrorManager.shared.alert(error: error)
    }
    withAnimation {
      isLoading = false
    }
  }

  private func loadMore() async {
    guard pagination.hasMorePages && !isLoadingMore else { return }
    withAnimation {
      isLoadingMore = true
    }
    do {
      let page = try await MediaManagementService.getMediaAnalysisBooks(
        statuses: selectedStatuses,
        libraryIds: selectedLibraryIds.isEmpty ? nil : Array(selectedLibraryIds),
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      withAnimation {
        _ = pagination.applyPage(page.content)
        pagination.advance(moreAvailable: !page.last)
      }
      lastTriggeredItemId = nil
    } catch {
      lastTriggeredItemId = nil
      ErrorManager.shared.alert(error: error)
    }
    withAnimation {
      isLoadingMore = false
    }
  }
}
