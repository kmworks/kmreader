//
// EpubTocSheetView.swift
//
//

#if os(iOS) || os(macOS)
  import SwiftUI

  struct EpubTocSheetView: View {
    let chapters: [WebPubLink]
    let currentLink: WebPubLink?
    let bookmarks: [EpubBookmark]
    let currentBookmarkID: UUID?
    let goToChapter: (WebPubLink) -> Void
    let goToBookmark: (EpubBookmark) -> Void
    let deleteBookmark: (EpubBookmark) -> Void

    @State private var tab: TocTab

    init(
      chapters: [WebPubLink],
      currentLink: WebPubLink?,
      bookmarks: [EpubBookmark],
      currentBookmarkID: UUID?,
      goToChapter: @escaping (WebPubLink) -> Void,
      goToBookmark: @escaping (EpubBookmark) -> Void,
      deleteBookmark: @escaping (EpubBookmark) -> Void
    ) {
      self.chapters = chapters
      self.currentLink = currentLink
      self.bookmarks = bookmarks
      self.currentBookmarkID = currentBookmarkID
      self.goToChapter = goToChapter
      self.goToBookmark = goToBookmark
      self.deleteBookmark = deleteBookmark
      _tab = State(initialValue: chapters.isEmpty && !bookmarks.isEmpty ? .bookmarks : .contents)
    }

    /// Rows for links with an href keep the href as their scroll identity;
    /// href-less container headings get a path-based id so siblings never
    /// collide.
    static func rowID(for link: WebPubLink, path: String) -> String {
      link.href ?? "heading:\(path)"
    }

    var body: some View {
      SheetView(title: String(localized: "title.chapters"), size: .large, applyFormStyle: true) {
        ScrollViewReader { proxy in
          List {
            Section {
              Picker("Contents", selection: $tab) {
                Text("Contents").tag(TocTab.contents)
                Text("Bookmarks").tag(TocTab.bookmarks)
              }
              .pickerStyle(.segmented)
              .labelsHidden()
            }

            switch tab {
            case .contents:
              ForEach(Array(chapters.enumerated()), id: \.offset) { index, link in
                ChapterRow(
                  link: link,
                  rowID: Self.rowID(for: link, path: "\(index)"),
                  currentLink: currentLink,
                  goToChapter: goToChapter
                )
              }
            case .bookmarks:
              if bookmarks.isEmpty {
                emptyBookmarksSection
              } else {
                ForEach(bookmarks) { bookmark in
                  BookmarkRow(
                    bookmark: bookmark,
                    isCurrent: bookmark.id == currentBookmarkID,
                    goToBookmark: goToBookmark,
                    deleteBookmark: deleteBookmark
                  )
                }
              }
            }
          }
          .optimizedListStyle()
          .onAppear {
            DispatchQueue.main.async {
              if let target = currentLink, let href = target.href {
                proxy.scrollTo(href, anchor: .center)
              }
            }
          }
        }
      }
      .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var emptyBookmarksSection: some View {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Label("No Bookmarks", systemImage: "bookmark.slash")
            .font(.headline)
          Text("Bookmark a page to return to it later.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
      }
    }
  }

  private enum TocTab: Hashable {
    case contents
    case bookmarks
  }

  private struct BookmarkRow: View {
    let bookmark: EpubBookmark
    let isCurrent: Bool
    let goToBookmark: (EpubBookmark) -> Void
    let deleteBookmark: (EpubBookmark) -> Void

    var body: some View {
      Button {
        goToBookmark(bookmark)
      } label: {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(bookmark.chapterTitle ?? bookmark.chapterHref)
            Text(bookmark.totalProgression.formatted(.percent.precision(.fractionLength(1))))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if isCurrent {
            Image(systemName: AppIcon.bookmark)
              .symbolVariant(.fill)
              .foregroundStyle(.secondary)
          }
        }
        .contentShape(Rectangle())
      }
      .adaptiveButtonStyle(.plain)
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) {
          HapticFeedback.light()
          deleteBookmark(bookmark)
        } label: {
          Label("Delete", systemImage: AppIcon.delete)
        }
      }
    }
  }

  private struct ChapterRow: View {
    let link: WebPubLink
    let rowID: String
    let currentLink: WebPubLink?
    let goToChapter: (WebPubLink) -> Void

    @State private var isExpanded: Bool = false

    init(link: WebPubLink, rowID: String, currentLink: WebPubLink?, goToChapter: @escaping (WebPubLink) -> Void) {
      self.link = link
      self.rowID = rowID
      self.currentLink = currentLink
      self.goToChapter = goToChapter

      // Initialize isExpanded based on whether this group contains the current link
      if let children = link.children, !children.isEmpty, let currentHref = currentLink?.href {
        _isExpanded = State(initialValue: Self.containsLink(currentHref, in: children))
      }
    }

    var body: some View {
      if let children = link.children, !children.isEmpty {
        DisclosureGroup(isExpanded: $isExpanded) {
          ForEach(Array(children.enumerated()), id: \.offset) { index, child in
            ChapterRow(
              link: child,
              rowID: EpubTocSheetView.rowID(for: child, path: "\(rowID)/\(index)"),
              currentLink: currentLink,
              goToChapter: goToChapter
            )
          }
        } label: {
          Button {
            goToChapter(link)
          } label: {
            ChapterLabel(link: link, currentLink: currentLink)
              .contentShape(Rectangle())
          }
          .adaptiveButtonStyle(.plain)
        }
        .id(rowID)
      } else {
        Button {
          goToChapter(link)
        } label: {
          ChapterLabel(link: link, currentLink: currentLink)
            .contentShape(Rectangle())
        }
        .adaptiveButtonStyle(.plain)
        .id(rowID)
      }
    }

    private static func containsLink(_ href: String, in links: [WebPubLink]) -> Bool {
      for link in links {
        if link.href == href {
          return true
        }
        if let children = link.children, containsLink(href, in: children) {
          return true
        }
      }
      return false
    }
  }

  private struct ChapterLabel: View {
    let link: WebPubLink
    let currentLink: WebPubLink?

    var isCurrent: Bool {
      guard let currentHref = currentLink?.href else { return false }
      return currentHref == link.href
    }

    var body: some View {
      HStack {
        Text(link.title ?? link.href ?? "")
          .foregroundStyle(isCurrent ? .secondary : .primary)
        Spacer()
        if isCurrent {
          Image(systemName: "circle.fill")
            .imageScale(.small)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
#endif
