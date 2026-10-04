//
// OfflineDownloadedBookGroupView.swift
//
//

import SwiftUI

struct OfflineDownloadedBookGroupView: View {
  enum TitleStyle {
    case numbered
    case oneshot

    func title(for book: OfflineDownloadedBookItem) -> String {
      switch self {
      case .numbered:
        return book.listTitle
      case .oneshot:
        return book.oneshotTitle
      }
    }
  }

  let groupId: String
  let title: String
  let books: [OfflineDownloadedBookItem]
  let titleStyle: TitleStyle
  let reloadToken: Int
  let onDeleteBook: (OfflineDownloadedBookItem) -> Void
  let onDeleteBooks: ([OfflineDownloadedBookItem]) -> Void

  @State private var isExpanded = false
  @State private var isLoadingProtectionSources = false
  @State private var loadedBookIds: [String] = []
  @State private var loadedReloadToken: Int?
  @State private var protectionSourcesByBookId: [String: [OfflineProtectionSource]] = [:]

  private static let formatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.allowedUnits = .useAll
    f.countStyle = .file
    return f
  }()

  private var bookIds: [String] {
    books.map(\.bookId)
  }

  var body: some View {
    #if os(tvOS)
      Section(header: header) {
        rows
      }
      .task(id: reloadToken) {
        await loadProtectionSourcesIfNeeded()
      }
    #else
      DisclosureGroup(isExpanded: $isExpanded) {
        rows
      } label: {
        header
      }
      .onChange(of: isExpanded) { _, isExpanded in
        if isExpanded {
          Task {
            await loadProtectionSourcesIfNeeded()
          }
        }
      }
      .onChange(of: reloadToken) { _, _ in
        if isExpanded {
          Task {
            await loadProtectionSourcesIfNeeded()
          }
        }
      }
      .swipeActions(edge: .trailing) {
        Button(role: .destructive) {
          HapticFeedback.medium()
          onDeleteBooks(books)
        } label: {
          Label(String(localized: "Delete All"), systemImage: "trash")
        }.optimizedControlSize()
      }
    #endif
  }

  private var header: some View {
    HStack {
      Text(title)
      OfflineCountBadge(count: books.count)
      Spacer()
      downloadedMetrics(size: downloadedSize)
    }
  }

  private var rows: some View {
    ForEach(books) { book in
      HStack {
        Text(titleStyle.title(for: book))
          .font(.footnote)

        Spacer()
        if book.isReadCompleted {
          Image(systemName: "checkmark.circle")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        OfflineProtectionSourcesMenu(sources: protectionSourcesByBookId[book.bookId] ?? [])
        Text(Self.formatter.string(fromByteCount: book.downloadedSize))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      #if !os(tvOS)
        .swipeActions(edge: .trailing) {
          Button(role: .destructive) {
            HapticFeedback.medium()
            onDeleteBook(book)
          } label: {
            Label(String(localized: "Delete"), systemImage: "trash")
          }.optimizedControlSize()
        }
      #endif
    }
  }

  private var downloadedSize: Int64 {
    books.reduce(0) { $0 + $1.downloadedSize }
  }

  private func downloadedMetrics(size: Int64) -> some View {
    Text(Self.formatter.string(fromByteCount: size))
      .font(.caption)
      .foregroundColor(.secondary)
      .lineLimit(1)
  }

  private func loadProtectionSourcesIfNeeded() async {
    guard !bookIds.isEmpty else { return }
    guard loadedBookIds != bookIds || loadedReloadToken != reloadToken else { return }
    guard !isLoadingProtectionSources else { return }

    isLoadingProtectionSources = true
    defer {
      isLoadingProtectionSources = false
    }

    do {
      let database = try await DatabaseOperator.database()
      let sourcesByBookId = try await database.fetchOfflineProtectionSources(
        instanceId: books[0].instanceId,
        bookIds: bookIds
      )
      var updatedSources = protectionSourcesByBookId
      for bookId in bookIds {
        updatedSources[bookId] = sourcesByBookId[bookId] ?? []
      }
      protectionSourcesByBookId = updatedSources
      loadedBookIds = bookIds
      loadedReloadToken = reloadToken
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
