//
// WholeSpreadPresentation.swift
//
//

/// How a page host shows a whole spread: which physical side its start edge is
/// on, and the edge it opens at when the host starts showing it.
struct WholeSpreadPresentation: Equatable {
  let pageID: ReaderPageID
  let startsAtLeft: Bool
  let arrivalEdge: ReaderSpreadEdge
}
