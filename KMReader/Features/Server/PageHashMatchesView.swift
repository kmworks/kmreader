//
// PageHashMatchesView.swift
//
//

import SwiftUI

struct PageHashMatchesView: View {
  let hash: String

  @State private var matches: [PageHashMatch] = []
  @State private var isLoading = false

  var body: some View {
    Form {
      if isLoading {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else if matches.isEmpty {
        Section {
          Text(String(localized: "No matches found"))
            .foregroundColor(.secondary)
        }
      } else {
        Section {
          ForEach(matches) { match in
            matchRow(match: match)
          }
        }
      }
    }
    .task {
      await loadMatches()
    }
  }

  @ViewBuilder
  private func matchRow(match: PageHashMatch) -> some View {
    HStack(spacing: 12) {
      // Page thumbnail (downloaded through ThumbnailCache so the request
      // carries the same auth headers as every other API call; AsyncImage has
      // no way to attach X-Auth-Token / X-API-Key and would 401 under
      // stateless API-key auth).
      PageHashMatchThumbnailView(
        bookId: match.bookId,
        pageNumber: match.pageNumber
      )

      VStack(alignment: .leading, spacing: 4) {
        Text(match.fileName)
          .lineLimit(1)

        Text(match.url)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)

        HStack(spacing: 12) {
          Label(
            String(localized: "Page \(match.pageNumber)"),
            systemImage: "doc"
          )
          .font(.caption)
          .foregroundColor(.secondary)

          Text(match.mediaType)
            .font(.caption)
            .foregroundColor(.secondary)

          Text(
            ByteCountFormatter.string(
              fromByteCount: match.fileSize, countStyle: .binary)
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }

      Spacer()

      Button(role: .destructive) {
        Task { await deleteMatch(match) }
      } label: {
        Image(systemName: AppIcon.delete)
          .foregroundColor(.red)
      }
      .buttonStyle(.borderless)
    }
  }

  private func deleteMatch(_ match: PageHashMatch) async {
    do {
      try await MediaManagementService.deleteMatchByHash(hash, match: match)
      withAnimation {
        matches.removeAll { $0.id == match.id }
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func loadMatches() async {
    withAnimation {
      isLoading = true
    }
    do {
      let page = try await MediaManagementService.getPageHashMatches(
        hash: hash,
        page: 0,
        size: 100
      )
      withAnimation {
        matches = page.content
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
    withAnimation {
      isLoading = false
    }
  }
}

/// Thumbnail for a single page-hash match, loaded via ThumbnailCache so the
/// download carries the same authentication headers as every other API request.
private struct PageHashMatchThumbnailView: View {
  let bookId: String
  let pageNumber: Int

  private enum LoadState {
    case loading
    case loaded(PlatformImage)
    case failed
  }

  @State private var state: LoadState = .loading

  var body: some View {
    Group {
      switch state {
      case .loading:
        // Keep the same spinner the previous AsyncImage showed while loading.
        ProgressView()
          .frame(width: 50, height: 70)
      case .loaded(let image):
        Image(platformImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 50, height: 70)
          .clipShape(RoundedRectangle(cornerRadius: 4))
      case .failed:
        placeholder
      }
    }
    .task(id: "\(bookId)#\(pageNumber)") {
      state = .loading
      if let image = await ThumbnailCache.shared.image(
        id: bookId, type: .page, page: pageNumber)
      {
        state = .loaded(image)
      } else {
        state = .failed
      }
    }
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(.secondary.opacity(0.2))
      .frame(width: 50, height: 70)
      .overlay {
        Image(systemName: "photo")
          .foregroundColor(.secondary)
      }
  }
}
