//
// SidebarView.swift
//
//

import SwiftUI

struct SidebarView: View {
  @Binding var selection: NavDestination?

  @Environment(\.colorScheme) private var colorScheme

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false

  @AppStorage("sidebarLibrariesExpanded") private var librariesExpanded: Bool = true

  @State private var isRefreshing: Bool = false
  @State private var store = SidebarItemsStore()

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
    // monochrome (near-black/near-white) accent.
    #if os(iOS) || os(macOS)
      .listStyle(.sidebar)
    #endif
    #if os(iOS)
      // iOS paints the selection pill with the accent, which inverts the
      // selected row against the near-white dark-mode accent; repaint the
      // pill a neutral gray there, matching the macOS source-list selection.
      .tint(colorScheme == .dark ? Color(uiColor: .systemGray4) : Color.accentColor)
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

  /// With the dark-mode sidebar tinted gray, selected and unselected rows
  /// share the same primary content color; light mode leaves the system's
  /// forced-white content on the accent pill alone.
  @ViewBuilder
  private func sidebarRowContent<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    if colorScheme == .dark {
      content().foregroundStyle(.primary)
    } else {
      content()
    }
  }

  @ViewBuilder
  private var listContent: some View {
    Section {
      NavigationLink(value: NavDestination.home) {
        sidebarRowContent {
          Label(String(localized: "tab.home"), systemImage: "house")
        }
      }
      NavigationLink(value: NavDestination.offline) {
        sidebarRowContent {
          Label(TabItem.offline.title, systemImage: TabItem.offline.icon)
        }
      }
      NavigationLink(value: NavDestination.server) {
        sidebarRowContent {
          Label(TabItem.server.title, systemImage: TabItem.server.icon)
        }
      }
    }

    if !store.libraries.isEmpty {
      Section(isExpanded: librariesExpandedBinding) {
        ForEach(store.libraries) { library in
          let destination = NavDestination.browseLibrary(
            selection: LibrarySelection(sidebarItem: library))
          NavigationLink(value: destination) {
            sidebarRowContent {
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
        }
      } header: {
        Label(String(localized: "Libraries"), systemImage: ContentIcon.library)
      }
    }

    Section {
      NavigationLink(value: NavDestination.browseCollections) {
        sidebarRowContent {
          SidebarItemLabel(
            title: String(localized: "tab.collections"),
            count: store.collectionsCount,
            systemImage: ContentIcon.collection
          )
        }
      }
      NavigationLink(value: NavDestination.browseReadLists) {
        sidebarRowContent {
          SidebarItemLabel(
            title: String(localized: "tab.readLists"),
            count: store.readListsCount,
            systemImage: ContentIcon.readList
          )
        }
      }
    }

    if showsSettingsLink {
      Section {
        NavigationLink(value: NavDestination.settings) {
          sidebarRowContent {
            TabItem.settings.label
          }
        }
      }
    }
  }
}
