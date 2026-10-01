//
// CollectionsBrowseView.swift
//
//

import SwiftUI

struct CollectionsBrowseView: View {
  let libraryIds: [String]
  let searchText: String
  let refreshTrigger: UUID
  @Binding var showFilterSheet: Bool

  @AppStorage("collectionSortOptions") private var sortOpts: SimpleSortOptions =
    SimpleSortOptions()
  @AppStorage("collectionBrowseLayout") private var browseLayout: BrowseLayoutMode = .grid
  @State private var viewModel = CollectionsViewModel()
  @State private var hasInitialized = false

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: browseLayout.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  var body: some View {
    VStack {
      CollectionSortView(showFilterSheet: $showFilterSheet, layoutMode: $browseLayout)
        .padding(.horizontal)

      BrowseStateView(
        isLoading: viewModel.isLoading,
        isEmpty: viewModel.pagination.isEmpty,
        emptyIcon: ContentIcon.collection,
        emptyTitle: LocalizedStringKey("No collections found"),
        emptyMessage: LocalizedStringKey("Try selecting a different library."),
        onRetry: {
          Task {
            await loadCollections(refresh: true)
          }
        }
      ) {
        switch browseLayout {
        case .grid, .largeGrid:
          LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(viewModel.pagination.items) { collection in
              CollectionQueryItemView(
                collectionId: collection.id,
                layout: browseLayout,
                onItemMissing: {
                  viewModel.removeCollection(id: collection.id)
                }
              )
              .onAppear {
                if viewModel.pagination.shouldLoadMore(after: collection) {
                  Task {
                    await loadCollections(refresh: false)
                  }
                }
              }
            }
          }
          .padding(.horizontal)
        case .list:
          LazyVStack {
            ForEach(viewModel.pagination.items) { collection in
              CollectionQueryItemView(
                collectionId: collection.id,
                layout: .list,
                onItemMissing: {
                  viewModel.removeCollection(id: collection.id)
                }
              )
              .onAppear {
                if viewModel.pagination.shouldLoadMore(after: collection) {
                  Task {
                    await loadCollections(refresh: false)
                  }
                }
              }
              if !viewModel.pagination.isLast(collection) {
                Divider()
              }
            }
          }
          .padding(.horizontal)
        }
      }
    }
    .task {
      guard !hasInitialized else { return }
      hasInitialized = true
      await loadCollections(refresh: true)
    }
    .onChange(of: refreshTrigger) { _, _ in
      Task {
        await loadCollections(refresh: true)
      }
    }
    .onChange(of: sortOpts) { oldValue, newValue in
      if oldValue != newValue {
        Task {
          await loadCollections(refresh: true)
        }
      }
    }
    .onChange(of: searchText) { _, _ in
      Task {
        await loadCollections(refresh: true)
      }
    }
  }

  private func loadCollections(refresh: Bool) async {
    await viewModel.loadCollections(
      libraryIds: libraryIds,
      searchText: searchText,
      sort: sortOpts.sortString,
      refresh: refresh
    )
  }
}
