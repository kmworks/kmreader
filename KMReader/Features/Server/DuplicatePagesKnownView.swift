//
// DuplicatePagesKnownView.swift
//
//

import SwiftUI

struct DuplicatePagesKnownView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var hasLoaded = false
  @State private var pagination = PaginationState<PageHashKnown>(pageSize: 10)
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var lastTriggeredItemId: String?

  @State private var filterActions: Set<PageHashAction> = [.deleteAuto, .deleteManual]
  @State private var selectedMatchHash: String = ""
  @State private var showingMatchSheet = false
  @State private var hashPendingDeleteMatches: PageHashKnown?
  @State private var hashPendingDeleteAuto: PageHashKnown?

  private var isDeleteMatchesAlertPresented: Binding<Bool> {
    Binding(
      get: { hashPendingDeleteMatches != nil },
      set: { if !$0 { hashPendingDeleteMatches = nil } }
    )
  }

  private var isDeleteAutoAlertPresented: Binding<Bool> {
    Binding(
      get: { hashPendingDeleteAuto != nil },
      set: { if !$0 { hashPendingDeleteAuto = nil } }
    )
  }

  private func filterActionBinding(_ action: PageHashAction) -> Binding<Bool> {
    Binding(
      get: { filterActions.contains(action) },
      set: { isOn in
        if isOn {
          filterActions.insert(action)
        } else {
          filterActions.remove(action)
        }
      }
    )
  }

  var body: some View {
    List {
      if !current.isAdmin {
        AdminRequiredView()
      } else {
        filterSection
        contentSection
      }
    }
    .optimizedListStyle()
    .platformNavigationTitle(String(localized: "Known Duplicates"))
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
    .onChange(of: filterActions) {
      Task { await loadData(refresh: true) }
    }
    .sheet(isPresented: $showingMatchSheet) {
      SheetView(title: String(localized: "Matches"), size: .large, applyFormStyle: true) {
        PageHashMatchesView(hash: selectedMatchHash)
      }
    }
    .alert(String(localized: "Delete Matches?"), isPresented: isDeleteMatchesAlertPresented) {
      if let hashPendingDeleteMatches {
        Button(String(localized: "Delete"), role: .destructive) {
          Task { await deleteMatches(hash: hashPendingDeleteMatches) }
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
      }
    } message: {
      if let hashPendingDeleteMatches {
        Text(
          "This will permanently delete \(hashPendingDeleteMatches.matchCount) matched pages from Komga. This action cannot be undone."
        )
      }
    }
    .alert(String(localized: "Auto Delete?"), isPresented: isDeleteAutoAlertPresented) {
      if let hashPendingDeleteAuto {
        Button(String(localized: "Delete"), role: .destructive) {
          Task { await updateAction(hash: hashPendingDeleteAuto, action: .deleteAuto) }
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
      }
    } message: {
      Text(
        "The server will automatically delete all pages matching this hash. This action cannot be undone."
      )
    }
  }

  private var filterSection: some View {
    Section(String(localized: "Filters")) {
      ForEach(PageHashAction.allCases, id: \.self) { action in
        Toggle(
          action.label,
          isOn: filterActionBinding(action)
        )
      }
    }
  }

  @ViewBuilder
  private var contentSection: some View {
    if isLoading && pagination.isEmpty {
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
            Text(String(localized: "No known duplicates"))
              .foregroundColor(.secondary)
          }
          Spacer()
        }
        .padding(.vertical)
      }
    } else {
      ForEach(pagination.items) { hash in
        Section {
          knownHashCard(hash: hash)
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
    }
  }

  @ViewBuilder
  private func knownHashCard(hash: PageHashKnown) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      // Hash + action badge
      HStack {
        Text(hash.hash.prefix(16) + "...")
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)

        Spacer()

        Text(hash.action.label)
          .font(.caption2)
          .fontWeight(.semibold)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(actionColor(hash.action).opacity(0.15), in: Capsule())
          .foregroundColor(actionColor(hash.action))
      }

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

        if hash.deleteCount > 0 {
          VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Deleted"))
              .font(.caption2)
              .foregroundColor(.secondary)
            Text("\(hash.deleteCount)")
              .font(.caption)
          }
        }
      }

      // Space metrics
      if let size = hash.size, size > 0 {
        HStack(spacing: 16) {
          if hash.deleteCount > 0 {
            Label(
              String(
                localized:
                  "\(ByteCountFormatter.string(fromByteCount: size * Int64(hash.deleteCount), countStyle: .binary)) saved"
              ),
              systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundColor(.green)
          }

          if hash.matchCount > 0 {
            Label(
              String(
                localized:
                  "Can save \(ByteCountFormatter.string(fromByteCount: size * Int64(hash.matchCount), countStyle: .binary))"
              ),
              systemImage: "arrow.down.circle"
            )
            .font(.caption)
            .foregroundColor(.secondary)
          }
        }
      }

      Divider()

      // Action buttons
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

        if hash.action == .deleteManual, hash.matchCount > 0 {
          Button {
            hashPendingDeleteMatches = hash
          } label: {
            Label(String(localized: "Delete Matches"), systemImage: "trash")
              .font(.caption)
          }
          .adaptiveButtonStyle(.bordered)
          .controlSize(.small)
          .tint(.red)
        }
      }

      // Action change buttons
      HStack(spacing: 8) {
        if hash.action != .ignore {
          Button {
            Task { await updateAction(hash: hash, action: .ignore) }
          } label: {
            Text(PageHashAction.ignore.label)
              .font(.caption)
          }
          .adaptiveButtonStyle(.bordered)
          .controlSize(.small)
        }

        if hash.action != .deleteManual {
          Button {
            Task { await updateAction(hash: hash, action: .deleteManual) }
          } label: {
            Text(PageHashAction.deleteManual.label)
              .font(.caption)
          }
          .adaptiveButtonStyle(.bordered)
          .controlSize(.small)
        }

        if hash.action != .deleteAuto, hash.size != nil {
          Button {
            hashPendingDeleteAuto = hash
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

  private func actionColor(_ action: PageHashAction) -> Color {
    switch action {
    case .deleteAuto: return .green
    case .deleteManual: return .orange
    case .ignore: return .secondary
    }
  }

  private func updateAction(hash: PageHashKnown, action: PageHashAction) async {
    do {
      try await MediaManagementService.createOrUpdatePageHash(
        PageHashCreation(hash: hash.hash, size: hash.size, action: action)
      )
      await loadData(refresh: true)
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func deleteMatches(hash: PageHashKnown) async {
    do {
      try await MediaManagementService.deleteAllMatchesByHash(hash.hash)
      ErrorManager.shared.notify(
        message: String(localized: "Matches deleted")
      )
      await loadData(refresh: true)
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func loadData(refresh: Bool) async {
    let actions = Array(filterActions)
    guard !actions.isEmpty else {
      withAnimation {
        pagination.reset()
        _ = pagination.applyPage([])
      }
      return
    }

    if refresh {
      withAnimation {
        pagination.reset()
      }
      lastTriggeredItemId = nil
    }

    withAnimation {
      isLoading = true
    }
    do {
      let page = try await MediaManagementService.getKnownPageHashes(
        actions: actions,
        page: pagination.currentPage,
        size: pagination.pageSize,
        sort: "deleteCount,desc"
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
      let page = try await MediaManagementService.getKnownPageHashes(
        actions: Array(filterActions),
        page: pagination.currentPage,
        size: pagination.pageSize,
        sort: "deleteCount,desc"
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
