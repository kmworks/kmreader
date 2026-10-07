//
// SmartListDetailView.swift
//
//

import SwiftUI

struct SmartListDetailView: View {
  let smartListId: String

  @AppStorage("currentAccount") private var current: Current = .init()

  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @State private var smartList: SmartList?
  @State private var loadedSmartListId: String?
  @State private var hasError = false
  @State private var showDeleteConfirmation = false
  @State private var showEditSheet = false
  /// Measured detail-column width driving the single/two-column layout switch.
  /// Defaults wide where the wide layout can engage (iPad, macOS) so the first
  /// frame doesn't flash the single column.
  #if os(macOS)
    @State private var detailContentWidth: CGFloat = .infinity
  #else
    @State private var detailContentWidth: CGFloat = PlatformHelper.isPad ? .infinity : 0
  #endif

  init(smartListId: String) {
    self.smartListId = smartListId
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

  private var navigationTitle: String {
    smartList?.name ?? String(localized: "title.smartList", defaultValue: "Smart List")
  }

  private var canDelete: Bool {
    guard let smartList else { return false }
    return smartList.ownerId == current.userId || current.isAdmin
  }

  var body: some View {
    Group {
      if usesWideLayout {
        if let smartList {
          SmartListDetailWideLayoutView(
            smartList: smartList,
            availableWidth: detailContentWidth
          )
        } else if hasError {
          smartListLoadFailureView
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      } else {
        ScrollView {
          VStack(alignment: .leading) {
            if let smartList {
              #if os(tvOS)
                smartListToolbarContent
                  .padding(.vertical, 8)
              #endif

              SmartListDetailContentView(smartList: smartList)
                .padding(.horizontal)

              switch smartList.target {
              case .book:
                SmartListBooksListView(smartListId: smartList.id)
              case .series:
                SmartListSeriesListView(smartListId: smartList.id)
              }
            } else if hasError {
              smartListLoadFailureView
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
    .platformNavigationTitle(navigationTitle)
    .komgaHandoff(
      title: navigationTitle,
      url: KomgaWebLinkBuilder.smartList(serverURL: current.serverURL, smartListId: smartListId),
      scope: .browse
    )
    .alert("Delete Smart List?", isPresented: $showDeleteConfirmation) {
      Button("Delete", role: .destructive) {
        Task {
          await deleteSmartList()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently delete \(smartList?.name ?? "this smart list") from the server.")
    }
    .sheet(isPresented: $showEditSheet) {
      if let smartList {
        SmartListEditSheet(mode: .edit(smartList))
      }
    }
    #if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .automatic) {
          smartListToolbarContent
        }
      }
    #endif
    .task {
      guard loadedSmartListId != smartListId else { return }
      loadedSmartListId = smartListId
      await loadSmartList()
    }
    .onReceive(NotificationCenter.default.publisher(for: .smartListsDidChange)) { notification in
      guard notification.userInfo?["smartListId"] as? String == smartListId else { return }
      Task {
        await loadSmartList()
      }
    }
  }
}

// Helper functions for SmartListDetailView
extension SmartListDetailView {
  private func loadSmartList() async {
    hasError = false
    do {
      smartList = try await SmartListService.getSmartList(id: smartListId)
    } catch {
      if case APIError.notFound = error {
        dismiss()
      } else if smartList == nil {
        hasError = true
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  @ViewBuilder
  private var smartListLoadFailureView: some View {
    ContentUnavailableView {
      Label("Failed to load smart list details", systemImage: AppIcon.loadError)
    } actions: {
      Button(String(localized: "Retry")) {
        Task {
          await loadSmartList()
        }
      }
      .adaptiveButtonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @MainActor
  private func deleteSmartList() async {
    do {
      try await SmartListService.deleteSmartList(smartListId: smartListId)
      ErrorManager.shared.notify(
        message: String(localized: "notification.smartList.deleted", defaultValue: "Smart list deleted"))
      dismiss()
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func refreshCover() {
    Task {
      do {
        try await ThumbnailCache.refreshThumbnail(id: smartListId, type: .smartList)
        ErrorManager.shared.notify(
          message: String(localized: "notification.smartList.coverRefreshed", defaultValue: "Cover refreshed"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  @ViewBuilder
  private var smartListToolbarContent: some View {
    Menu {
      if canDelete {
        Button {
          deferMenuActionPresentation { showEditSheet = true }
        } label: {
          Label("Edit", systemImage: AppIcon.edit)
        }
      }

      Button {
        refreshCover()
      } label: {
        Label("Refresh Cover", systemImage: AppIcon.refresh)
      }

      if canDelete {
        Divider()

        Button(role: .destructive) {
          showDeleteConfirmation = true
        } label: {
          Label("Delete Smart List", systemImage: AppIcon.delete)
        }
      }
    } label: {
      Image(systemName: AppIcon.more)
    }
    .toolbarButtonStyle()
  }
}
