//
// DuplicateFilesView.swift
//
//

import SwiftUI

struct DuplicateFilesView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var hasLoaded = false
  @State private var books: [Book] = []
  @State private var isLoading = false
  @State private var totalElements = 0
  @State private var currentPage = 0
  @State private var hasMore = true

  var body: some View {
    List {
      if !current.isAdmin {
        AdminRequiredView()
      } else if isLoading && books.isEmpty {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else if books.isEmpty {
        Section {
          emptyState
        }
      } else {
        ForEach(groupedBooks, id: \.hash) { group in
          Section {
            ForEach(group.books) { book in
              duplicateFileRow(book: book)
            }
          } header: {
            HStack {
              Text(group.hash.prefix(16) + "...")
                .font(.system(.caption, design: .monospaced))
              Spacer()
              Text(
                String(
                  localized: "\(group.books.count) files"
                )
              )
              .font(.caption)
            }
          }
        }

        if hasMore {
          Section {
            HStack {
              Spacer()
              Button {
                Task { await loadMore() }
              } label: {
                if isLoading {
                  ProgressView()
                } else {
                  Text(String(localized: "Load More"))
                }
              }
              .disabled(isLoading)
              Spacer()
            }
            .padding(.vertical, 4)
          }
        }
      }
    }
    .optimizedListStyle()
    .platformNavigationTitle(String(localized: "Duplicate Files"))
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
  }

  private var emptyState: some View {
    HStack {
      Spacer()
      VStack(spacing: 8) {
        Image(systemName: "checkmark.circle")
          .font(.system(size: 40))
          .foregroundColor(.green)
        Text(String(localized: "No duplicate files found"))
          .foregroundColor(.secondary)
      }
      Spacer()
    }
    .padding(.vertical)
  }

  private var groupedBooks: [DuplicateGroup] {
    var dict: [String: [Book]] = [:]
    var order: [String] = []
    for book in books {
      let hash = book.fileHash ?? ""
      if dict[hash] == nil {
        order.append(hash)
      }
      dict[hash, default: []].append(book)
    }
    return order.map { DuplicateGroup(hash: $0, books: dict[$0] ?? []) }
  }

  @ViewBuilder
  private func duplicateFileRow(book: Book) -> some View {
    NavigationLink(value: NavDestination.bookDetail(bookId: book.id)) {
      HStack(spacing: 12) {
        ThumbnailImage(
          id: book.id,
          type: .book,
          shadowStyle: .none,
          width: 40,
          cornerRadius: 4,
          isTransitionSource: false
        )

        VStack(alignment: .leading, spacing: 4) {
          Text(book.name)
            .lineLimit(2)

          Text(book.url)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)

          HStack(spacing: 8) {
            Text(book.size)
              .font(.caption)
              .foregroundColor(.secondary)

            if book.deleted {
              unavailableBadge
            }
          }
        }
      }
    }
  }

  private var unavailableBadge: some View {
    Text(String(localized: "Unavailable"))
      .font(.caption2)
      .fontWeight(.semibold)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.red.opacity(0.15), in: Capsule())
      .foregroundColor(.red)
  }

  private func loadData(refresh: Bool) async {
    if refresh {
      withAnimation {
        currentPage = 0
        hasMore = true
        books = []
      }
    }

    withAnimation {
      isLoading = true
    }
    do {
      let page = try await MediaManagementService.getDuplicateBooks(
        page: currentPage,
        size: 50,
        sort: "fileHash,asc"
      )
      withAnimation {
        if refresh {
          books = page.content
        } else {
          books.append(contentsOf: page.content)
        }
        totalElements = page.totalElements
        hasMore = !page.last
        currentPage += 1
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
    withAnimation {
      isLoading = false
    }
  }

  private func loadMore() async {
    guard hasMore && !isLoading else { return }
    await loadData(refresh: false)
  }
}

private struct DuplicateGroup {
  let hash: String
  let books: [Book]
}
