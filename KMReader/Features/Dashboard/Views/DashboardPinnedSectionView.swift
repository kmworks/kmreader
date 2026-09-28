//
// DashboardPinnedSectionView.swift
//
//

import SwiftUI

@MainActor
struct DashboardPinnedSectionView: View {
  let section: DashboardSection

  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var viewModel: DashboardPinnedSectionViewModel
  @State private var collectionPendingDelete: CollectionDisplayItem?
  @State private var readListPendingDelete: ReadListDisplayItem?
  @State private var showCollectionDeleteConfirmation = false
  @State private var showReadListDeleteConfirmation = false

  init(section: DashboardSection) {
    self.section = section
    _viewModel = State(initialValue: DashboardPinnedSectionViewModel(section: section))
  }

  private var isSupportedSection: Bool {
    switch section.contentKind {
    case .collections, .readLists:
      return true
    default:
      return false
    }
  }

  private var hasItems: Bool {
    switch section.contentKind {
    case .collections:
      return !viewModel.pinnedCollections.isEmpty
    case .readLists:
      return !viewModel.pinnedReadLists.isEmpty
    default:
      return false
    }
  }

  private var itemIds: [String] {
    switch section.contentKind {
    case .collections:
      return viewModel.pinnedCollections.map(\.collectionId)
    case .readLists:
      return viewModel.pinnedReadLists.map(\.readListId)
    default:
      return []
    }
  }

  private var destination: NavDestination {
    switch section.contentKind {
    case .collections:
      return .browseCollections
    case .readLists:
      return .browseReadLists
    default:
      return .browseCollections
    }
  }

  private var horizontalCardWidth: CGFloat {
    LayoutConfig.horizontalCardWidth
  }

  private var horizontalCoverWidth: CGFloat {
    LayoutConfig.horizontalCoverWidth
  }

  var body: some View {
    if isSupportedSection {
      DashboardSectionLayout(
        section: section,
        destination: destination,
        showsCardKindMenu: false,
        isEmpty: !hasItems,
        itemIds: itemIds
      ) {
        LazyHStack(alignment: .top, spacing: LayoutConfig.defaultSpacing) {
          switch section.contentKind {
          case .collections:
            ForEach(viewModel.pinnedCollections) { collection in
              CollectionHorizontalCardView(
                item: collection,
                coverWidth: horizontalCoverWidth,
                onChanged: schedulePinnedItemsReload,
                onDeleteRequested: {
                  collectionPendingDelete = collection
                  showCollectionDeleteConfirmation = true
                }
              )
              .id(collection.collectionId)
              .frame(width: horizontalCardWidth)
            }
          case .readLists:
            ForEach(viewModel.pinnedReadLists) { readList in
              ReadListHorizontalCardView(
                item: readList,
                coverWidth: horizontalCoverWidth,
                onChanged: schedulePinnedItemsReload,
                onDeleteRequested: {
                  readListPendingDelete = readList
                  showReadListDeleteConfirmation = true
                }
              )
              .id(readList.readListId)
              .frame(width: horizontalCardWidth)
            }
          default:
            EmptyView()
          }
        }
      }
      .alert("Delete Collection", isPresented: $showCollectionDeleteConfirmation) {
        Button("Cancel", role: .cancel) {
          collectionPendingDelete = nil
        }
        Button("Delete", role: .destructive) {
          deletePendingCollection()
        }
      } message: {
        Text("Are you sure you want to delete this collection? This action cannot be undone.")
      }
      .alert("Delete Read List", isPresented: $showReadListDeleteConfirmation) {
        Button("Cancel", role: .cancel) {
          readListPendingDelete = nil
        }
        Button("Delete", role: .destructive) {
          deletePendingReadList()
        }
      } message: {
        Text("Are you sure you want to delete this read list? This action cannot be undone.")
      }
      .onReceive(NotificationCenter.default.publisher(for: .dashboardSectionsShouldReload)) {
        notification in
        guard
          let command = DashboardSectionRefreshNotifier.reloadCommand(from: notification),
          command.includes(section)
        else {
          return
        }
        let instanceId = currentInstanceId
        Task {
          defer {
            DashboardRefreshCoordinator.shared.acknowledgeSectionReload(
              commandID: command.id, section: section)
          }
          await viewModel.refresh(instanceId: instanceId)
        }
      }
      .onAppear {
        DashboardRefreshCoordinator.shared.registerSection(section)
        viewModel.refreshIfNeeded(instanceId: currentInstanceId)
      }
      .onDisappear {
        DashboardRefreshCoordinator.shared.unregisterSection(section)
      }
      .onChange(of: currentInstanceId) { _, instanceId in
        viewModel.refreshIfNeeded(instanceId: instanceId)
      }
    }
  }

  private var currentInstanceId: String {
    current.instanceId
  }

  private func schedulePinnedItemsReload() {
    Task {
      await viewModel.loadPinnedItems(instanceId: currentInstanceId)
    }
  }

  private func deletePendingCollection() {
    guard let collection = collectionPendingDelete else { return }
    Task {
      defer { collectionPendingDelete = nil }
      do {
        try await CollectionService.deleteCollection(collectionId: collection.collectionId)
        ErrorManager.shared.notify(message: String(localized: "notification.collection.deleted"))
        await viewModel.loadPinnedItems(instanceId: currentInstanceId)
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func deletePendingReadList() {
    guard let readList = readListPendingDelete else { return }
    Task {
      defer { readListPendingDelete = nil }
      do {
        try await ReadListService.deleteReadList(readListId: readList.readListId)
        ErrorManager.shared.notify(message: String(localized: "notification.readList.deleted"))
        await viewModel.loadPinnedItems(instanceId: currentInstanceId)
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
