//
// BookDetailContentView.swift
//
//

import SwiftUI

struct BookDetailContentView: View {
  let book: Book
  let downloadStatus: DownloadStatus?
  let protectionSources: [OfflineProtectionSource]
  let inSheet: Bool

  @AppStorage("thumbnailBlurUnreadCovers") private var thumbnailBlurUnreadCovers: Bool = false

  /// Measured width driving the centered/leading header switch. Defaults wide
  /// where the leading layout can engage (iPad, macOS) so the first frame
  /// doesn't flash centered.
  #if os(macOS)
    @State private var contentWidth: CGFloat = .infinity
  #else
    @State private var contentWidth: CGFloat = PlatformHelper.isPad ? .infinity : 0
  #endif

  private let collapsedLinkLimit = 6

  init(
    book: Book,
    downloadStatus: DownloadStatus?,
    protectionSources: [OfflineProtectionSource] = [],
    inSheet: Bool
  ) {
    self.book = book
    self.downloadStatus = downloadStatus
    self.protectionSources = protectionSources
    self.inSheet = inSheet
  }

  private var coverBlurRadius: CGFloat {
    thumbnailBlurUnreadCovers && book.isUnread ? CoverBlurStyle.unreadRadius : 0
  }

  private var isNarrowLayout: Bool {
    contentWidth < LayoutConfig.detailWideLayoutMinimumWidth
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Group {
        DetailHeroView(
          id: book.id,
          type: .book,
          contentBlurRadius: coverBlurRadius
        ) {
          VStack(alignment: isNarrowLayout ? .center : .leading, spacing: 6) {
            if !inSheet {
              NavigationLink(value: NavDestination.seriesDetail(seriesId: book.seriesId)) {
                HStack(spacing: 4) {
                  Image(systemName: ContentIcon.series)
                  Text(book.seriesTitle)
                    .lineLimit(1)
                  Image(systemName: "chevron.right")
                    .font(.caption2)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }

            DetailTitleView(title: book.metadata.title)

            DetailChipFlow(items: authorItems, collapsedLimit: 4)

            DetailHeroMetadataGroup {
              if let releaseDate = book.metadata.releaseDate {
                DetailMetadataRow(
                  systemImage: "calendar",
                  text: Text("Release Date: \(releaseDate)")
                )
              }

              if let isbn = book.metadata.isbn, !isbn.isEmpty {
                DetailMetadataRow(
                  systemImage: "barcode",
                  text: Text(isbn)
                )
              }
            }
          }
        }

        DetailActionCard {
          VStack(alignment: isNarrowLayout ? .center : .leading, spacing: 2) {
            let mediaStatus = book.media.statusValue
            let number = book.metadata.number
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              if mediaStatus != .ready {
                Label(mediaStatus.label, systemImage: mediaStatus.icon)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(mediaStatus.detailColor)
              } else {
                if !number.isEmpty {
                  Text(verbatim: "#\(number)")
                    .font(.subheadline.weight(.semibold))
                }
                Text("\(book.media.pagesCount) pages")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }

              if book.deleted {
                Label("Unavailable", systemImage: "exclamationmark.circle")
                  .font(.caption)
                  .foregroundStyle(.red)
              } else if let readProgress = book.readProgress {
                if book.isCompleted {
                  Label("Completed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                  Label(
                    "Page \(readProgress.page) / \(book.media.pagesCount)",
                    systemImage: "circle.righthalf.filled"
                  )
                  .font(.caption)
                  .foregroundStyle(.orange)
                }
              } else {
                Label("Unread", systemImage: "circle")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              if let downloadStatus, let icon = downloadStatus.displayIcon {
                if !isNarrowLayout {
                  Spacer()
                }
                OfflineProtectionStatusChip(
                  label: downloadStatus.displayLabel,
                  systemImage: icon,
                  spinning: downloadStatus.isPending,
                  color: downloadStatus.displayColor,
                  sources: protectionSources
                )
              }
            }

            if let readProgress = book.readProgress, !book.deleted {
              Label(
                "Last Read: \(readProgress.readDate.formattedMediumDate)",
                systemImage: "book.closed"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)

          if !inSheet {
            BookActionsSection(
              book: book,
              downloadStatus: downloadStatus
            )
          }
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)

        DetailTimestampsView(created: book.created, lastModified: book.lastModified)
          .frame(maxWidth: .infinity, alignment: isNarrowLayout ? .center : .leading)
      }
      .environment(\.detailHeroCentered, isNarrowLayout)

      if let summary = book.metadata.summary, !summary.isEmpty {
        ExpandableSummaryView(
          summary: summary,
          titleIcon: nil,
          subtitle: nil,
          titleStyle: .headline
        )
      }

      DetailChipFlow(items: tagItems, collapsedLimit: collapsedLinkLimit, glass: false)

      DetailChipFlow(items: linkItems, collapsedLimit: collapsedLinkLimit)

      BookMediaInfoSection(book: book)
    }
    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
  }

  private var authorItems: [DetailChipFlow.Item] {
    (book.metadata.authors ?? []).sortedByRole().map {
      .init(
        title: $0.name,
        systemImage: $0.role.icon,
        destination: .navigate(MetadataFilterHelper.booksDestinationForAuthor($0.name))
      )
    }
  }

  private var tagItems: [DetailChipFlow.Item] {
    (book.metadata.tags ?? []).localizedSorted().map {
      .init(
        title: $0,
        systemImage: "tag",
        destination: .navigate(MetadataFilterHelper.booksDestinationForTag($0))
      )
    }
  }

  private var linkItems: [DetailChipFlow.Item] {
    (book.metadata.links ?? []).compactMap { link in
      URL(string: link.url).map {
        .init(title: link.label, systemImage: "link", destination: .external($0))
      }
    }
  }
}
