//
// EpubTocSheetView.swift
//
//

#if os(iOS) || os(macOS)
  import SwiftUI

  struct EpubTocSheetView: View {
    let chapters: [WebPubLink]
    let currentLink: WebPubLink?
    let goToChapter: (WebPubLink) -> Void

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
            ForEach(Array(chapters.enumerated()), id: \.offset) { index, link in
              ChapterRow(
                link: link,
                rowID: Self.rowID(for: link, path: "\(index)"),
                currentLink: currentLink,
                goToChapter: goToChapter
              )
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
          .buttonStyle(.plain)
        }
        .id(rowID)
      } else {
        Button {
          goToChapter(link)
        } label: {
          ChapterLabel(link: link, currentLink: currentLink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
          Image(systemName: "bookmark.fill")
        }
      }
    }
  }
#endif
