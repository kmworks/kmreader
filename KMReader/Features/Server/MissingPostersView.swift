//
// MissingPostersView.swift
//
//

import SwiftUI

struct MissingPostersView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var hasLoaded = false
  @State private var pagination = PaginationState<Book>(pageSize: 20)
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var lastTriggeredItemId: String?

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
              Text(String(localized: "No missing posters"))
                .foregroundColor(.secondary)
            }
            Spacer()
          }
          .padding(.vertical)
        }
      } else {
        Section {
          ForEach(pagination.items) { book in
            missingPosterRow(book: book)
          }

          if isLoadingMore {
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
    .optimizedListStyle()
    .platformNavigationTitle(String(localized: "Missing Posters"))
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

  @ViewBuilder
  private func missingPosterRow(book: Book) -> some View {
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
          Text(book.seriesTitle)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)

          Text(book.metadata.title)
            .lineLimit(2)

          HStack(spacing: 8) {
            if !book.media.mediaType.isEmpty {
              Text(book.media.mediaType)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if book.deleted {
              Text(String(localized: "Unavailable"))
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.15), in: Capsule())
                .foregroundColor(.red)
            }
          }
        }
      }
    }
    .onAppear {
      guard pagination.hasMorePages,
        !isLoadingMore,
        pagination.shouldLoadMore(after: book, threshold: 3),
        lastTriggeredItemId != book.id
      else { return }
      lastTriggeredItemId = book.id
      Task { await loadMore() }
    }
  }

  private func loadData(refresh: Bool) async {
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
      let page = try await MediaManagementService.getMissingPosterBooks(
        page: pagination.currentPage,
        size: pagination.pageSize
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
      let page = try await MediaManagementService.getMissingPosterBooks(
        page: pagination.currentPage,
        size: pagination.pageSize
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
