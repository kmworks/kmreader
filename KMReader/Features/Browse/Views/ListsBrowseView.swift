//
// ListsBrowseView.swift
//
//

import SwiftUI

/// Lists page: Collections and Read Lists as two horizontal strips, pinned
/// items first, fed by the same view models as the full single-type pages the
/// section headers link to. The library scope filters both strips.
struct ListsBrowseView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = .init()

  @State private var collectionsViewModel = CollectionsViewModel(pageSize: 20)
  @State private var readListsViewModel = ReadListsViewModel(pageSize: 20)
  @State private var scopeStore = LibraryScopeStore()
  @State private var browseScope: LibraryBrowseScope?
  @State private var showLibraryPicker = false
  @State private var initialLoadDone = false

  private var effectiveScope: LibraryBrowseScope {
    browseScope ?? .pinned
  }

  private var resolvedLibraryIds: [String] {
    effectiveScope.resolvedIds(pinned: dashboard.libraryIds)
  }

  private var resolvedLibraryIdsKey: String {
    resolvedLibraryIds.joined(separator: ",")
  }

  private var scopeMenuBinding: Binding<LibraryBrowseScope> {
    Binding(get: { effectiveScope }, set: { browseScope = $0 })
  }

  private var isCompletelyEmpty: Bool {
    initialLoadDone
      && !collectionsViewModel.isLoading && !readListsViewModel.isLoading
      && collectionsViewModel.pagination.isEmpty && readListsViewModel.pagination.isEmpty
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
        }
      }
    }
    .inlineLargeBarTitleStyle()
    .platformNavigationTitle(String(localized: "tab.lists", defaultValue: "Lists"))
    .refreshable {
      await reloadAll()
    }
    .toolbar {
      #if os(iOS)
        if !PlatformHelper.isPad, #available(iOS 26.0, *) {
          ToolbarItem(placement: .largeTitle) {
            InlineLargeBarTitle(title: String(localized: "tab.lists", defaultValue: "Lists"))
          }
        }
      #endif
      #if os(macOS)
        ToolbarItem(placement: .navigation) {
          LibraryScopeMenu(
            libraries: scopeStore.libraries,
            showLibraryPicker: $showLibraryPicker,
            scope: scopeMenuBinding)
        }
      #endif
      #if os(iOS)
        if PlatformHelper.isPad {
          ToolbarItem(placement: .cancellationAction) {
            LibraryScopeMenu(
              libraries: scopeStore.libraries,
              showLibraryPicker: $showLibraryPicker,
              scope: scopeMenuBinding)
          }
        } else {
          ToolbarItem(placement: .confirmationAction) {
            LibraryScopeMenu(
              libraries: scopeStore.libraries,
              showLibraryPicker: $showLibraryPicker,
              scope: scopeMenuBinding)
          }
        }
      #endif
    }
    .sheet(isPresented: $showLibraryPicker) {
      LibraryPickerSheet()
    }
    .task(id: "\(current.instanceId)|\(resolvedLibraryIdsKey)") {
      await reloadAll()
      initialLoadDone = true
    }
    .task(id: current.instanceId) {
      await scopeStore.refresh(instanceId: current.instanceId)
    }
    .onReceive(NotificationCenter.default.publisher(for: .sidebarProjectionDidChange)) { notification in
      guard notification.userInfo?["instanceId"] as? String == current.instanceId else { return }
      Task {
        await scopeStore.load(instanceId: current.instanceId)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .collectionProjectionDidChange)) { _ in
      Task {
        await collectionsViewModel.loadCollections(
          libraryIds: resolvedLibraryIds, refresh: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .readListProjectionDidChange)) { _ in
      Task {
        await readListsViewModel.loadReadLists(
          libraryIds: resolvedLibraryIds, refresh: true)
      }
    }
    .onChange(of: scopeStore.libraries) { _, libraries in
      // A scoped library that vanished falls back to the aggregate.
      guard !libraries.isEmpty else { return }
      if let scopedId = browseScope?.libraryId,
        !libraries.contains(where: { $0.libraryId == scopedId })
      {
        browseScope = nil
      }
    }
    .onChange(of: dashboard.libraryIds) { _, pinnedIds in
      // The Pinned item only exists while pins do; an emptied pinned set is
      // the full set, which All already represents.
      guard pinnedIds.isEmpty, browseScope == .pinned else { return }
      browseScope = .all
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
      }
    }
  }

  private func reloadAll() async {
    async let loadCollections: Void = collectionsViewModel.loadCollections(
      libraryIds: resolvedLibraryIds, refresh: true)
    async let loadReadLists: Void = readListsViewModel.loadReadLists(
      libraryIds: resolvedLibraryIds, refresh: true)
    _ = await (loadCollections, loadReadLists)
  }
}
