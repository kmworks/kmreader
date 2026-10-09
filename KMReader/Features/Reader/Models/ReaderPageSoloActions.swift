//
// ReaderPageSoloActions.swift
//
//

import Foundation

enum ReaderPageSoloActions {
  struct Action: Identifiable, Equatable {
    let id: String
    let pageID: ReaderPageID
    let title: String
    let systemImage: String
  }

  static func resolve(
    supportsDualPageOptions: Bool,
    dualPage: Bool,
    readingDirection: ReadingDirection,
    currentPageID: ReaderPageID?,
    currentPairIDs: (first: ReaderPageID, second: ReaderPageID?)?,
    isCurrentPageWide: Bool,
    isCurrentPageSolo: Bool,
    displayPageNumber: (ReaderPageID) -> Int
  ) -> [Action] {
    guard supportsDualPageOptions else { return [] }
    guard let currentPageID else { return [] }
    guard !isCurrentPageWide else { return [] }

    if isCurrentPageSolo {
      return [
        Action(
          id: "cancel-\(currentPageID.description)",
          pageID: currentPageID,
          title: String(localized: "Cancel Solo"),
          systemImage: "rectangle.portrait.slash"
        )
      ]
    }

    guard dualPage, let currentPairIDs, let secondPageID = currentPairIDs.second else { return [] }

    let leftPageID = readingDirection == .rtl ? secondPageID : currentPairIDs.first
    let rightPageID = readingDirection == .rtl ? currentPairIDs.first : secondPageID

    return [
      Action(
        id: "solo-\(leftPageID.description)",
        pageID: leftPageID,
        title: String.localizedStringWithFormat(
          String(localized: "Show Page %d Solo"),
          displayPageNumber(leftPageID)
        ),
        systemImage: "rectangle.lefthalf.inset.filled"
      ),
      Action(
        id: "solo-\(rightPageID.description)",
        pageID: rightPageID,
        title: String.localizedStringWithFormat(
          String(localized: "Show Page %d Solo"),
          displayPageNumber(rightPageID)
        ),
        systemImage: "rectangle.righthalf.inset.filled"
      ),
    ]
  }
}
