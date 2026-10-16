import CoreGraphics
import Foundation

struct NativeEndPagePresentation {
  enum SectionDisplayMode {
    case both
    case previousOnly
    case nextOnly
  }

  enum LayoutMode {
    case singlePrevious
    case singleNext
    case stacked
    case sideBySide(nextOnLeadingSide: Bool, showsRelationHeader: Bool)
  }

  struct Section {
    let isVisible: Bool
    let badgeText: String?
    let bookID: String?
    let title: String?
    let detail: String?
    let showsCover: Bool
    let showsMetadata: Bool
    let showsCaughtUp: Bool
    /// Offline state of this section's book while it is the segment's next book.
    let nextBookOfflineState: NextBookOfflineState?
    /// Remaining unread line for the finished book's series (series context only).
    let unreadRemainingText: String?
  }

  let relationTitle: String
  let previous: Section
  let next: Section
  let showsCloseButton: Bool

  static func make(
    previousBook: Book?,
    nextBook: Book?,
    readListContext: ReaderReadListContext?,
    sectionDisplayMode: SectionDisplayMode = .both,
    nextBookOfflineState: NextBookOfflineState? = nil,
    remainingUnreadCount: Int? = nil
  ) -> NativeEndPagePresentation {
    // End page sits between the finished book and its next sibling.
    // `previousBook` intentionally represents the finished/current segment book shown on the leading side.
    let relationTitle = readListContext?.name ?? previousBook?.seriesTitle ?? nextBook?.seriesTitle ?? ""
    let previousVisible = sectionDisplayMode != .nextOnly && previousBook != nil
    let nextVisible = sectionDisplayMode != .previousOnly
    // A read list page reports list order, not series membership: the series
    // unread count would read as a list statistic there.
    let unreadText = readListContext == nil ? unreadRemainingText(for: remainingUnreadCount) : nil

    let previousSection = Section(
      isVisible: previousVisible,
      badgeText: previousVisible ? String(localized: "reader.previousBook").uppercased() : nil,
      bookID: previousVisible ? previousBook?.id : nil,
      title: previousVisible ? previousBook?.readerChapterTitle : nil,
      detail: previousVisible ? previousBook?.readerChapterDetail : nil,
      showsCover: previousVisible,
      showsMetadata: previousVisible,
      showsCaughtUp: false,
      nextBookOfflineState: nil,
      unreadRemainingText: nil
    )

    let nextSection = Section(
      isVisible: nextVisible,
      badgeText: nextBook != nil && nextVisible ? String(localized: "reader.nextBook").uppercased() : nil,
      bookID: nextVisible ? nextBook?.id : nil,
      title: nextVisible ? nextBook?.readerChapterTitle : nil,
      detail: nextVisible ? nextBook?.readerChapterDetail : nil,
      showsCover: nextBook != nil && nextVisible,
      showsMetadata: nextBook != nil && nextVisible,
      showsCaughtUp: nextBook == nil && nextVisible,
      nextBookOfflineState: nextBook != nil ? nextBookOfflineState : nil,
      unreadRemainingText: unreadText
    )

    return NativeEndPagePresentation(
      relationTitle: relationTitle,
      previous: previousSection,
      next: nextSection,
      showsCloseButton: nextSection.showsCaughtUp
    )
  }

  static func unreadRemainingText(for count: Int?) -> String? {
    guard let count, count > 0 else { return nil }
    return String(localized: "\(count) unread left")
  }

  func layoutMode(for size: CGSize, readingDirection: ReadingDirection) -> LayoutMode {
    if previous.isVisible && next.isVisible {
      if size.height >= size.width {
        return .stacked
      }
      return .sideBySide(
        nextOnLeadingSide: readingDirection == .rtl,
        showsRelationHeader: !relationTitle.isEmpty
      )
    }

    if previous.isVisible {
      return .singlePrevious
    }

    return .singleNext
  }
}
