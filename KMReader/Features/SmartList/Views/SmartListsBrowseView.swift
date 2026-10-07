//
// SmartListsBrowseView.swift
//
//

import SwiftUI

struct SmartListsBrowseView: View {
  let searchText: String
  let refreshTrigger: UUID

  @AppStorage("smartListBrowseLayout") private var browseLayout: BrowseLayoutMode = .grid
  @State private var viewModel = SmartListsViewModel()
  @State private var hasInitialized = false
  @State private var showCreateSheet = false

  private var columns: [GridItem] {
    LayoutConfig.adaptiveColumns(cardWidth: browseLayout.cardWidth)
  }

  private var spacing: CGFloat {
    LayoutConfig.defaultSpacing
  }

  /// The endpoint has no search param, so the submitted query filters the
  /// unpaged list client-side.
  private var displayedSmartLists: [SmartList] {
    guard !searchText.isEmpty else { return viewModel.smartLists }
    return viewModel.smartLists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
  }

  private var emptyMessage: LocalizedStringKey {
    searchText.isEmpty
      ? LocalizedStringKey("Smart lists are saved searches kept up to date by the server.")
      : LocalizedStringKey("Try a different search.")
  }

  var body: some View {
    VStack {
      HStack(spacing: 8) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            LayoutModeMenu(selection: $browseLayout)
          }
          .padding(4)
        }
        .scrollClipDisabled()

        if viewModel.isSupported {
          Button {
            showCreateSheet = true
          } label: {
            Image(systemName: AppIcon.add)
          }
          .adaptiveButtonStyle(.bordered)
          .optimizedControlSize()
        }
      }
      .padding(.horizontal)

      if !viewModel.isSupported {
        ContentUnavailableView {
          Label(
            String(localized: "smartlist.unavailable.title", defaultValue: "Smart Lists"),
            systemImage: ContentIcon.smartList)
        } description: {
          Text(
            String(
              localized: "smartlist.unavailable.description",
              defaultValue: "This feature requires a kmrs server."))
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else {
        BrowseStateView(
          isLoading: viewModel.isLoading,
          isEmpty: displayedSmartLists.isEmpty,
          emptyIcon: ContentIcon.smartList,
          emptyTitle: LocalizedStringKey("No smart lists found"),
          emptyMessage: emptyMessage,
          onRetry: {
            Task {
              await loadSmartLists(refresh: true)
            }
          },
          emptyActions: {
            if searchText.isEmpty {
              Button {
                showCreateSheet = true
              } label: {
                Label("New Smart List", systemImage: AppIcon.add)
              }
              .adaptiveButtonStyle(.borderedProminent)
            }
          }
        ) {
          switch browseLayout {
          case .grid, .largeGrid:
            LazyVGrid(columns: columns, spacing: spacing) {
              ForEach(displayedSmartLists) { smartList in
                SmartListCardView(
                  smartList: smartList,
                  cardWidth: browseLayout.cardWidth
                )
              }
            }
            .padding(.horizontal)
          case .list:
            LazyVStack {
              ForEach(displayedSmartLists) { smartList in
                SmartListRowView(smartList: smartList)
                if smartList.id != displayedSmartLists.last?.id {
                  Divider()
                }
              }
            }
            .padding(.horizontal)
          }
        }
      }
    }
    .sheet(isPresented: $showCreateSheet) {
      SmartListEditSheet(mode: .create)
    }
    .task {
      guard !hasInitialized else { return }
      hasInitialized = true
      await loadSmartLists(refresh: true)
    }
    .onChange(of: refreshTrigger) { _, _ in
      Task {
        await loadSmartLists(refresh: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .smartListsDidChange)) { _ in
      Task {
        await loadSmartLists(refresh: true)
      }
    }
  }

  private func loadSmartLists(refresh: Bool) async {
    await viewModel.loadSmartLists(refresh: refresh)
  }
}
