//
// NativePageData.swift
//
//

import SwiftUI

/// Data structure for a single page to be rendered natively
struct NativePageData {
  let pageID: ReaderPageID
  let isLoading: Bool
  let failure: ReaderPageLoadFailure?
  let alignment: HorizontalAlignment
  let splitMode: PageSplitMode
  let rotation: ReaderRotation
  let animatedSourceFileURL: URL?

  init(
    pageID: ReaderPageID,
    isLoading: Bool,
    failure: ReaderPageLoadFailure? = nil,
    alignment: HorizontalAlignment,
    splitMode: PageSplitMode = .none,
    rotation: ReaderRotation = .none,
    animatedSourceFileURL: URL? = nil
  ) {
    self.pageID = pageID
    self.isLoading = isLoading
    self.failure = failure
    self.alignment = alignment
    self.splitMode = splitMode
    self.rotation = rotation
    self.animatedSourceFileURL = animatedSourceFileURL
  }
}
