//
// ListsBrowseContentView.swift
//
//

import SwiftUI

/// Content of the Lists page: the three horizontal strips. Reads the page's
/// view models directly so refresh-driven mutations re-render only this child;
/// the parent `ListsBrowseView` carries `.refreshable` and must stay untouched
/// by them (an active refresh action is cancelled once its view re-renders).
@MainActor
struct ListsBrowseContentView: View {
  let collectionsViewModel: CollectionsViewModel
  let readListsViewModel: ReadListsViewModel
  let smartListsViewModel: SmartListsViewModel
  let initialLoadDone: Bool
  let effectiveScope: LibraryBrowseScope

  @Environment(\.pushNavDestination) private var pushNavDestination

  private var isCompletelyEmpty: Bool {
    initialLoadDone
      && !collectionsViewModel.isLoading && !readListsViewModel.isLoading
      && !smartListsViewModel.isLoading
      && collectionsViewModel.pagination.isEmpty && readListsViewModel.pagination.isEmpty
      && smartListsViewModel.smartLists.isEmpty
  }

  var body: some View {
    ScrollView {
      if !initialLoadDone {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 320)
      } else if isCompletelyEmpty {
        ContentUnavailableView {
          Label(
            String(localized: "tab.lists", defaultValue: "Lists"), systemImage: ContentIcon.lists)
        } description: {
          Text(LocalizedStringKey("Try selecting a different library."))
        }
        .frame(maxWidth: .infinity, minHeight: 320)
      } else {
        VStack(spacing: 0) {
          section(
            title: BrowseContentType.collections.displayName,
            destination: .browseCollections(scope: effectiveScope),
            isEmpty: collectionsViewModel.pagination.isEmpty
          ) {
            ForEach(collectionsViewModel.pagination.items) { item in
              CollectionQueryItemView(
                collectionId: item.id,
                onItemMissing: {
                  collectionsViewModel.removeCollection(id: item.id)
                }
              )
              .id(item.id)
              .frame(width: LayoutConfig.gridCardWidth)
            }
          }
          section(
            title: BrowseContentType.readlists.displayName,
            destination: .browseReadLists(scope: effectiveScope),
            isEmpty: readListsViewModel.pagination.isEmpty
          ) {
            ForEach(readListsViewModel.pagination.items) { item in
              ReadListQueryItemView(
                readListId: item.id,
                onItemMissing: {
                  readListsViewModel.removeReadList(id: item.id)
                }
              )
              .id(item.id)
              .frame(width: LayoutConfig.gridCardWidth)
            }
          }
          section(
            title: BrowseContentType.smartlists.displayName,
            destination: .browseSmartLists,
            isEmpty: !smartListsViewModel.isSupported || smartListsViewModel.smartLists.isEmpty
          ) {
            ForEach(smartListsViewModel.smartLists.prefix(20)) { smartList in
              SmartListCardView(smartList: smartList)
                .id(smartList.id)
                .frame(width: LayoutConfig.gridCardWidth)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func section<Content: View>(
    title: String,
    destination: NavDestination,
    isEmpty: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if !isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        NavigationLink(value: destination) {
          HStack {
            Text(title)
              .font(.title2)
              .bold()
              .fontDesign(.serif)
            Image(systemName: "chevron.right")
              .foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, LayoutConfig.dashboardSectionTopPadding)

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: LayoutConfig.defaultSpacing) {
            content()
          }
          .padding(.top, LayoutConfig.dashboardSectionHeaderSpacing)
          .padding(.bottom, LayoutConfig.dashboardSectionBottomPadding(gradientBackground: false))
        }
        .contentMargins(.horizontal, LayoutConfig.defaultSpacing, for: .scrollContent)
        .scrollClipDisabled()
        .trailingOverscrollTrigger {
          pushNavDestination(destination)
        }
      }
    }
  }
}
