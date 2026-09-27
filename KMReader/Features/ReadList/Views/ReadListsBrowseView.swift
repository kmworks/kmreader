//
// ReadListsBrowseView.swift
//
//

import SwiftUI

struct ReadListsBrowseView: View {
  let libraryIds: [String]
  let searchText: String
  let refreshTrigger: UUID
  @Binding var showFilterSheet: Bool

  @AppStorage("readListSortOptions") private var sortOpts: SimpleSortOptions =
    SimpleSortOptions()
  @AppStorage("readListBrowseLayout") private var browseLayout: BrowseLayoutMode = .grid
  @State private var viewModel = ReadListsViewModel()
  @State private var hasInitialized = false

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: browseLayout.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  var body: some View {
    VStack {
      ReadListSortView(showFilterSheet: $showFilterSheet, layoutMode: $browseLayout)
        .padding(.horizontal)

      BrowseStateView(
        isLoading: viewModel.isLoading,
        isEmpty: viewModel.pagination.isEmpty,
        emptyIcon: ContentIcon.readList,
        emptyTitle: LocalizedStringKey("No read lists found"),
        emptyMessage: LocalizedStringKey("Try selecting a different library."),
        onRetry: {
          Task {
            await loadReadLists(refresh: true)
          }
        }
      ) {
        switch browseLayout {
        case .grid, .largeGrid:
          LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(viewModel.pagination.items) { readList in
              ReadListQueryItemView(
                readListId: readList.id,
                layout: browseLayout,
                onItemMissing: {
                  viewModel.removeReadList(id: readList.id)
                }
              )
              .padding(.bottom)
              .onAppear {
                if viewModel.pagination.shouldLoadMore(after: readList) {
                  Task {
                    await loadReadLists(refresh: false)
                  }
                }
              }
            }
          }
          .padding(.horizontal)
        case .list:
          LazyVStack {
            ForEach(viewModel.pagination.items) { readList in
              ReadListQueryItemView(
                readListId: readList.id,
                layout: .list,
                onItemMissing: {
                  viewModel.removeReadList(id: readList.id)
                }
              )
              .onAppear {
                if viewModel.pagination.shouldLoadMore(after: readList) {
                  Task {
                    await loadReadLists(refresh: false)
                  }
                }
              }
              if !viewModel.pagination.isLast(readList) {
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
      await loadReadLists(refresh: true)
    }
    .onChange(of: refreshTrigger) { _, _ in
      Task {
        await loadReadLists(refresh: true)
      }
    }
    .onChange(of: sortOpts) { oldValue, newValue in
      if oldValue != newValue {
        Task {
          await loadReadLists(refresh: true)
        }
      }
    }
    .onChange(of: searchText) { _, _ in
      Task {
        await loadReadLists(refresh: true)
      }
    }
  }

  private func loadReadLists(refresh: Bool) async {
    await viewModel.loadReadLists(
      libraryIds: libraryIds,
      searchText: searchText,
      sort: sortOpts.sortString,
      refresh: refresh
    )
  }
}
