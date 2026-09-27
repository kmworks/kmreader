//
// CollectionDetailView.swift
//
//

import SwiftUI

struct CollectionDetailView: View {
  let collectionId: String

  @AppStorage("currentAccount") private var current: Current = .init()

  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @State private var item: CollectionDisplayItem?
  @State private var loadedCollectionId: String?
  @State private var showDeleteConfirmation = false
  @State private var showEditSheet = false
  @State private var showFilterSheet = false
  @State private var showSavedFilters = false
  /// Measured detail-column width driving the single/two-column layout switch.
  /// Defaults wide where the wide layout can engage (iPad, macOS) so the first
  /// frame doesn't flash the single column.
  #if os(macOS)
    @State private var detailContentWidth: CGFloat = .infinity
  #else
    @State private var detailContentWidth: CGFloat = PlatformHelper.isPad ? .infinity : 0
  #endif

  init(collectionId: String) {
    self.collectionId = collectionId
  }

  /// The two-column layout engages only while the detail column is wide
  /// enough for it. iPad additionally requires regular width; macOS decides
  /// by window width alone.
  private var usesWideLayout: Bool {
    #if os(iOS)
      return PlatformHelper.isPad && horizontalSizeClass == .regular
        && detailContentWidth >= LayoutConfig.detailWideLayoutMinimumWidth
    #elseif os(macOS)
      return detailContentWidth >= LayoutConfig.detailWideLayoutMinimumWidth
    #else
      return false
    #endif
  }

  private var collection: SeriesCollection? {
    item?.collection
  }

  private var navigationTitle: String {
    collection?.name ?? String(localized: "title.collection")
  }

  private var isPinned: Bool {
    item?.isPinned ?? false
  }

  var body: some View {
    Group {
      if usesWideLayout {
        if let collection = collection {
          CollectionDetailWideLayoutView(
            collection: collection,
            item: item,
            collectionId: collectionId,
            availableWidth: detailContentWidth,
            showFilterSheet: $showFilterSheet,
            showSavedFilters: $showSavedFilters
          )
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      } else {
        ScrollView {
          VStack(alignment: .leading) {
            if let collection = collection {

              #if os(tvOS)
                collectionToolbarContent
                  .padding(.vertical, 8)
              #endif

              CollectionDetailContentView(
                collection: collection
              ).padding(.horizontal)

              // Series list
              if item != nil {
                CollectionSeriesListView(
                  collectionId: collectionId,
                  showFilterSheet: $showFilterSheet,
                  showSavedFilters: $showSavedFilters
                )
              }
            } else {
              ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
          .padding(.vertical)
        }
      }
    }
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) {
      detailContentWidth = $0
    }
    .inlineNavigationBarTitle(navigationTitle)
    .komgaHandoff(
      title: navigationTitle,
      url: KomgaWebLinkBuilder.collection(serverURL: current.serverURL, collectionId: collectionId),
      scope: .browse
    )
    .alert("Delete Collection?", isPresented: $showDeleteConfirmation) {
      Button("Delete", role: .destructive) {
        Task {
          await deleteCollection()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently delete \(collection?.name ?? "this collection") from Komga.")
    }
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .automatic) {
          collectionToolbarContent
        }
      }
    #endif
    .sheet(isPresented: $showEditSheet) {
      if let collection = collection {
        CollectionEditSheet(collection: collection)
          .onDisappear {
            Task {
              await loadCollectionDetails()
            }
          }
      }
    }
    .sheet(isPresented: $showSavedFilters) {
      SavedFiltersView(filterType: .collectionSeries)
    }
    .task {
      guard loadedCollectionId != collectionId else { return }
      loadedCollectionId = collectionId
      await loadCollectionDetails()
    }
    .onReceive(NotificationCenter.default.publisher(for: .collectionProjectionDidChange)) {
      notification in
      guard shouldHandleCollectionProjectionChange(notification) else { return }
      Task {
        await loadLocalCollection()
        if item == nil {
          dismiss()
        }
      }
    }
  }
}

// Helper functions for CollectionDetailView
extension CollectionDetailView {
  private func loadCollectionDetails() async {
    await loadLocalCollection()
    do {
      _ = try await SyncService.syncCollection(id: collectionId)
    } catch {
      if case APIError.notFound = error {
        dismiss()
      } else if item == nil {
        ErrorManager.shared.alert(error: error)
      }
    }
    await loadLocalCollection()
  }

  private func loadLocalCollection() async {
    guard let database = try? await DatabaseOperator.database() else {
      item = nil
      return
    }
    item = try? await database.fetchCollectionDisplayItem(
      collectionId: collectionId,
      instanceId: current.instanceId
    )
  }

  private func shouldHandleCollectionProjectionChange(_ notification: Notification) -> Bool {
    let changedIds = changedCollectionIds(from: notification)
    guard !changedIds.isEmpty else { return true }
    return changedIds.contains(collectionId)
  }

  private func changedCollectionIds(from notification: Notification) -> Set<String> {
    if let ids = notification.userInfo?["collectionIds"] as? Set<String> {
      return ids
    }
    if let ids = notification.userInfo?["collectionIds"] as? [String] {
      return Set(ids)
    }
    if let id = notification.userInfo?["collectionId"] as? String {
      return [id]
    }
    return []
  }

  @MainActor
  private func deleteCollection() async {
    do {
      try await CollectionService.deleteCollection(collectionId: collectionId)
      ErrorManager.shared.notify(message: String(localized: "notification.collection.deleted"))
      dismiss()
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func togglePinned() {
    guard let item else { return }
    let nextPinned = !item.isPinned
    Task {
      try? await DatabaseOperator.database().setCollectionPinned(
        collectionId: item.collectionId,
        instanceId: item.instanceId,
        isPinned: nextPinned
      )
      await loadLocalCollection()
    }
  }

  @ViewBuilder
  private var collectionToolbarContent: some View {
    actionsMenu
      .toolbarButtonStyle()
  }

  @ViewBuilder
  private var actionsMenu: some View {
    Menu {
      Button {
        togglePinned()
      } label: {
        Label(
          isPinned ? String(localized: "action.unpinFromTop") : String(localized: "action.pinToTop"),
          systemImage: isPinned ? "pin.slash" : "pin"
        )
      }

      if current.isAdmin {
        Divider()

        Button {
          showEditSheet = true
        } label: {
          Label("Edit", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
          showDeleteConfirmation = true
        } label: {
          Label("Delete Collection", systemImage: "trash")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
    }
  }
}
