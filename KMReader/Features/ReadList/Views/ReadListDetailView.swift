//
// ReadListDetailView.swift
//
//

import SwiftUI

struct ReadListDetailView: View {
  let readListId: String

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("readListContinuationEnabled") private var readListContinuationEnabled: Bool = false

  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @State private var item: ReadListDisplayItem?
  @State private var loadedReadListId: String?
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

  init(readListId: String) {
    self.readListId = readListId
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

  @ViewBuilder
  private var readListActions: some View {
    if let readList, readList.ordered, !readList.bookIds.isEmpty, !readListContinuationEnabled {
      ReadListContinuationHintView()
    }
    if let item {
      ReadListDownloadActionsSection(
        readListId: item.readListId,
        status: item.downloadStatus,
        policy: item.offlinePolicy,
        offlinePolicyLimit: item.offlinePolicyLimit,
        onMutationCompleted: {
          Task {
            await loadReadListDetails()
          }
        }
      )
    }
  }

  private var readList: ReadList? {
    item?.readList
  }

  private var navigationTitle: String {
    readList?.name ?? String(localized: "title.readList")
  }

  private var isPinned: Bool {
    item?.isPinned ?? false
  }

  var body: some View {
    Group {
      if usesWideLayout {
        if let readList = readList {
          ReadListDetailWideLayoutView(
            readList: readList,
            item: item,
            readListId: readListId,
            availableWidth: detailContentWidth,
            showFilterSheet: $showFilterSheet,
            showSavedFilters: $showSavedFilters
          ) {
            readListActions
          }
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      } else {
        ScrollView {
          VStack(alignment: .leading) {
            if let readList = readList {
              VStack(alignment: .leading) {
                #if os(tvOS)
                  readListToolbarContent
                    .padding(.vertical, 8)
                #endif

                ReadListDetailContentView(
                  readList: readList
                ) {
                  readListActions
                }
              }
              .padding(.horizontal)

              // Books list
              if item != nil {
                BooksListViewForReadList(
                  readListId: readListId,
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
      url: KomgaWebLinkBuilder.readList(serverURL: current.serverURL, readListId: readListId),
      scope: .browse
    )
    .alert("Delete Read List?", isPresented: $showDeleteConfirmation) {
      Button("Delete", role: .destructive) {
        Task {
          await deleteReadList()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently delete \(readList?.name ?? "this read list") from Komga.")
    }
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .automatic) {
          readListToolbarContent
        }
      }
    #endif
    .sheet(isPresented: $showEditSheet) {
      if let readList = readList {
        ReadListEditSheet(readList: readList)
          .onDisappear {
            Task {
              await loadReadListDetails()
            }
          }
      }
    }
    .sheet(isPresented: $showSavedFilters) {
      SavedFiltersView(filterType: .readListBooks)
    }
    .task {
      guard loadedReadListId != readListId else { return }
      loadedReadListId = readListId
      await loadReadListDetails()
    }
    .onReceive(NotificationCenter.default.publisher(for: .readListProjectionDidChange)) {
      notification in
      guard shouldHandleReadListProjectionChange(notification) else { return }
      Task {
        await loadLocalReadList()
        if item == nil {
          dismiss()
        }
      }
    }
  }
}

// Helper functions for ReadListDetailView
extension ReadListDetailView {
  private func loadReadListDetails() async {
    await loadLocalReadList()
    do {
      _ = try await SyncService.syncReadList(id: readListId)
    } catch {
      if case APIError.notFound = error {
        dismiss()
      } else if item == nil {
        ErrorManager.shared.alert(error: error)
      }
    }
    await loadLocalReadList()
  }

  private func loadLocalReadList() async {
    guard let database = try? await DatabaseOperator.database() else {
      item = nil
      return
    }
    item = try? await database.fetchReadListDisplayItem(
      readListId: readListId,
      instanceId: current.instanceId
    )
  }

  private func shouldHandleReadListProjectionChange(_ notification: Notification) -> Bool {
    let changedIds = changedReadListIds(from: notification)
    guard !changedIds.isEmpty else { return true }
    return changedIds.contains(readListId)
  }

  private func changedReadListIds(from notification: Notification) -> Set<String> {
    if let ids = notification.userInfo?["readListIds"] as? Set<String> {
      return ids
    }
    if let ids = notification.userInfo?["readListIds"] as? [String] {
      return Set(ids)
    }
    if let id = notification.userInfo?["readListId"] as? String {
      return [id]
    }
    return []
  }

  @MainActor
  private func deleteReadList() async {
    do {
      try await ReadListService.deleteReadList(readListId: readListId)
      ErrorManager.shared.notify(message: String(localized: "notification.readList.deleted"))
      dismiss()
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func togglePinned() {
    guard let item else { return }
    let nextPinned = !item.isPinned
    Task {
      try? await DatabaseOperator.database().setReadListPinned(
        readListId: item.readListId,
        instanceId: item.instanceId,
        isPinned: nextPinned
      )
      await loadLocalReadList()
    }
  }

  @ViewBuilder
  private var readListToolbarContent: some View {
    Menu {
      Button {
        togglePinned()
      } label: {
        Label(
          isPinned ? String(localized: "action.unpinFromTop") : String(localized: "action.pinToTop"),
          systemImage: isPinned ? "pin.slash" : "pin"
        )
      }

      ReadListStopReadingButton(readListId: readListId, instanceId: current.instanceId)

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
          Label("Delete Read List", systemImage: "trash")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
    }
    .toolbarButtonStyle()
  }
}
