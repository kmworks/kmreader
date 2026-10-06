//
// DuplicatePagesUnknownView.swift
//
//

import SwiftUI

struct DuplicatePagesUnknownView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var hasLoaded = false
  @State private var pagination = PaginationState<PageHashUnknown>(pageSize: 10)
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var lastTriggeredItemId: String?

  @State private var selectedMatchHash: String = ""
  @State private var showingMatchSheet = false
  @State private var processedHashes: Set<String> = []

  var body: some View {
    List {
      if !current.isAdmin {
        AdminRequiredView()
      } else if isLoading && pagination.isEmpty {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else if pagination.isEmpty {
        Section {
          HStack {
            Spacer()
            VStack(spacing: 8) {
              Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.green)
              Text(String(localized: "No unknown duplicates"))
                .foregroundColor(.secondary)
            }
            Spacer()
          }
          .padding(.vertical)
        }
      } else {
        ForEach(visibleItems) { hash in
          Section {
            unknownHashCard(hash: hash)
          }
          .onAppear {
            guard pagination.hasMorePages,
              !isLoadingMore,
              pagination.shouldLoadMore(after: hash, threshold: 3),
              lastTriggeredItemId != hash.id
            else { return }
            lastTriggeredItemId = hash.id
            Task { await loadMore() }
          }
        }

        if isLoadingMore {
          Section {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
            .padding(.vertical)
          }
        }

        if !visibleItems.isEmpty {
          Section(String(localized: "Bulk Actions")) {
            Button {
              Task { await markAllRemaining(.ignore) }
            } label: {
              Label(
                String(localized: "Ignore Remaining (\(visibleItems.count))"),
                systemImage: "eye.slash"
              )
            }

            Button(role: .destructive) {
              Task { await markAllRemaining(.deleteManual) }
            } label: {
              Label(
                String(localized: "Manual Delete Remaining (\(visibleItems.count))"),
                systemImage: AppIcon.delete
              )
            }

            Button(role: .destructive) {
              Task { await markAllRemaining(.deleteAuto) }
            } label: {
              Label(
                String(localized: "Auto Delete Remaining (\(visibleItems.count))"),
                systemImage: "trash.fill"
              )
            }
          }
        }
      }
    }
    .optimizedListStyle()
    .platformNavigationTitle(String(localized: "Unknown Duplicates"))
    .task {
      if current.isAdmin && !hasLoaded {
        await loadData(refresh: true)
        hasLoaded = true
      }
    }
    .refreshable {
      if current.isAdmin {
        await loadData(refresh: true)
      }
    }
    .sheet(isPresented: $showingMatchSheet) {
      SheetView(title: String(localized: "Matches"), size: .large, applyFormStyle: true) {
        PageHashMatchesView(hash: selectedMatchHash)
      }
    }
  }

  private var visibleItems: [PageHashUnknown] {
    pagination.items.filter { !processedHashes.contains($0.hash) }
  }

  @ViewBuilder
  private func unknownHashCard(hash: PageHashUnknown) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      // Hash
      Text(hash.hash.prefix(16) + "...")
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.secondary)

      // Stats
      HStack(spacing: 16) {
        if let size = hash.size, size > 0 {
          VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Size"))
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .binary))
              .font(.caption)
          }
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "Matches"))
            .font(.caption2)
            .foregroundColor(.secondary)
          Text("\(hash.matchCount)")
            .font(.caption)
        }

        if let size = hash.size, size > 0, hash.matchCount > 0 {
          VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Can Save"))
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(
              ByteCountFormatter.string(
                fromByteCount: size * Int64(hash.matchCount), countStyle: .binary)
            )
            .font(.caption)
            .foregroundColor(.secondary)
          }
        }
      }

      Divider()

      // Actions row
      HStack(spacing: 12) {
        if hash.matchCount > 0 {
          Button {
            selectedMatchHash = hash.hash
            showingMatchSheet = true
          } label: {
            Label(
              String(localized: "\(hash.matchCount) matches"),
              systemImage: "doc.on.doc"
            )
            .font(.caption)
          }
          .adaptiveButtonStyle(.bordered)
          .controlSize(.small)
        }

        Spacer()
      }

      // Action buttons
      HStack(spacing: 8) {
        Button {
          Task { await markHash(hash, action: .ignore) }
        } label: {
          Text(PageHashAction.ignore.label)
            .font(.caption)
        }
        .adaptiveButtonStyle(.bordered)
        .controlSize(.small)

        Button {
          Task { await markHash(hash, action: .deleteManual) }
        } label: {
          Text(PageHashAction.deleteManual.label)
            .font(.caption)
        }
        .adaptiveButtonStyle(.bordered)
        .controlSize(.small)

        if hash.size != nil {
          Button {
            Task { await markHash(hash, action: .deleteAuto) }
          } label: {
            Text(PageHashAction.deleteAuto.label)
              .font(.caption)
          }
          .adaptiveButtonStyle(.bordered)
          .controlSize(.small)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func markHash(_ hash: PageHashUnknown, action: PageHashAction) async {
    do {
      try await MediaManagementService.createOrUpdatePageHash(
        PageHashCreation(hash: hash.hash, size: hash.size, action: action)
      )
      withAnimation {
        _ = processedHashes.insert(hash.hash)
      }

      if visibleItems.isEmpty {
        await loadData(refresh: true)
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func markAllRemaining(_ action: PageHashAction) async {
    for hash in visibleItems {
      do {
        try await MediaManagementService.createOrUpdatePageHash(
          PageHashCreation(hash: hash.hash, size: hash.size, action: action)
        )
        withAnimation {
          _ = processedHashes.insert(hash.hash)
        }
      } catch {
        ErrorManager.shared.alert(error: error)
        return
      }
    }

    if visibleItems.isEmpty {
      await loadData(refresh: true)
    }
  }

  private func loadData(refresh: Bool) async {
    if refresh {
      withAnimation {
        pagination.reset()
        processedHashes.removeAll()
      }
      lastTriggeredItemId = nil
    }

    withAnimation {
      isLoading = true
    }
    do {
      let page = try await MediaManagementService.getUnknownPageHashes(
        page: pagination.currentPage,
        size: pagination.pageSize,
        sort: "matchCount,desc"
      )
      withAnimation {
        _ = pagination.applyPage(page.content)
        pagination.advance(moreAvailable: !page.last)
      }
      lastTriggeredItemId = nil
    } catch {
      lastTriggeredItemId = nil
      ErrorManager.shared.alert(error: error)
    }
    withAnimation {
      isLoading = false
    }
  }

  private func loadMore() async {
    guard pagination.hasMorePages && !isLoadingMore else { return }
    withAnimation {
      isLoadingMore = true
    }
    do {
      let page = try await MediaManagementService.getUnknownPageHashes(
        page: pagination.currentPage,
        size: pagination.pageSize,
        sort: "matchCount,desc"
      )
      withAnimation {
        _ = pagination.applyPage(page.content)
        pagination.advance(moreAvailable: !page.last)
      }
      lastTriggeredItemId = nil
    } catch {
      lastTriggeredItemId = nil
      ErrorManager.shared.alert(error: error)
    }
    withAnimation {
      isLoadingMore = false
    }
  }
}
