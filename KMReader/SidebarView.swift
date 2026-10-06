//
// SidebarView.swift
//
//

import SwiftUI

struct SidebarView: View {
  @Binding var selection: NavDestination?
  let store: SidebarItemsStore

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = .init()

  @AppStorage("sidebarLibrariesExpanded") private var librariesExpanded: Bool = true

  @State private var isRefreshing: Bool = false

  private var showsSettingsLink: Bool {
    #if os(iOS)
      return true
    #else
      return false
    #endif
  }

  private var librariesExpandedBinding: Binding<Bool> {
    Binding(
      get: { librariesExpanded },
      set: { setLibrariesExpanded($0) }
    )
  }

  private func refreshSidebar() async {
    guard !current.instanceId.isEmpty, !isRefreshing else { return }
    withAnimation {
      isRefreshing = true
    }
    ErrorManager.shared.notify(message: String(localized: "notification.refreshing"))
    defer {
      withAnimation {
        isRefreshing = false
      }
      ErrorManager.shared.notify(message: String(localized: "notification.refresh_completed"))
    }
    await SyncService.syncLibraries(instanceId: current.instanceId)
    await SyncService.syncCollections(instanceId: current.instanceId)
    await SyncService.syncReadLists(instanceId: current.instanceId)
    await store.load(instanceId: current.instanceId)
  }

  private func setLibrariesExpanded(_ isExpanded: Bool) {
    guard librariesExpanded != isExpanded else { return }
    withAnimation {
      librariesExpanded = isExpanded
    }
  }

  var body: some View {
    Group {
      List(selection: $selection) {
        listContent
      }
    }
    // macOS needs the sidebar style too: the default list style paints the
    // selection with the accent color, which is unreadable against the
    // monochrome (black/white) accent.
    #if os(iOS) || os(macOS)
      .listStyle(.sidebar)
    #endif
    #if os(iOS)
      .refreshable {
        await refreshSidebar()
      }
    #endif
    .task(id: current.instanceId) {
      await store.load(instanceId: current.instanceId)
    }
    .onReceive(NotificationCenter.default.publisher(for: .sidebarProjectionDidChange)) {
      notification in
      guard notification.userInfo?["instanceId"] as? String == current.instanceId else { return }
      Task {
        await store.load(instanceId: current.instanceId)
      }
    }
    #if os(macOS)
      .safeAreaInset(edge: .bottom) {
        Button {
          Task { await refreshSidebar() }
        } label: {
          HStack {
            if isRefreshing {
              ProgressView().controlSize(.small)
              Text(String(localized: "notification.refreshing"))
            } else {
              Image(systemName: "arrow.clockwise")
              Text(String(localized: "Refresh"))
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .disabled(isRefreshing)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
      }
    #endif
  }

  @ViewBuilder
  private var listContent: some View {
    Section {
      NavigationLink(value: NavDestination.home) {
        Label(TabItem.home.title, systemImage: "house")
      }
      NavigationLink(value: NavDestination.offline) {
        Label(TabItem.offline.title, systemImage: TabItem.offline.icon)
      }
      NavigationLink(value: NavDestination.server) {
        Label(TabItem.server.title, systemImage: TabItem.server.icon)
      }
    }

    if !store.libraries.isEmpty {
      Section(isExpanded: librariesExpandedBinding) {
        NavigationLink(value: NavDestination.browse(scope: .all)) {
          SidebarItemLabel(
            title: String(localized: "All Libraries"),
            count: nil
          )
        }
        if !dashboard.libraryIds.isEmpty {
          NavigationLink(value: NavDestination.browse(scope: .pinned)) {
            SidebarItemLabel(
              title: String(localized: "library.scope.pinned", defaultValue: "Pinned"),
              count: nil
            )
          }
        }
        ForEach(store.libraries) { library in
          let destination = NavDestination.browseLibrary(
            selection: LibrarySelection(sidebarItem: library))
          NavigationLink(value: destination) {
            SidebarItemLabel(
              title: library.name,
              count: library.displayBookCount
            )
            .contextMenu {
              if current.isAdmin && !isOffline {
                ForEach(LibraryAction.allCases, id: \.self) { action in
                  Button {
                    action.perform(for: library.libraryId)
                  } label: {
                    action.label
                  }
                }
              }
            }
          }
        }
      } header: {
        Text(String(localized: "Libraries"))
      }
    }

    Section {
      NavigationLink(value: NavDestination.browseCollections) {
        SidebarItemLabel(
          title: String(localized: "tab.collections"),
          count: store.collectionsCount,
          systemImage: ContentIcon.collection
        )
      }
      NavigationLink(value: NavDestination.browseReadLists) {
        SidebarItemLabel(
          title: String(localized: "tab.readLists"),
          count: store.readListsCount,
          systemImage: ContentIcon.readList
        )
      }
    }

    if showsSettingsLink {
      Section {
        NavigationLink(value: NavDestination.settings) {
          TabItem.settings.label
        }
      }
    }
  }
}
