//
// PageScrollControllerHost.swift
//
//

#if os(iOS) || os(tvOS)
  import UIKit

  /// A page host whose content lives in a `PageScrollController`.
  @MainActor
  protocol PageScrollControllerHost: AnyObject {
    /// Whether the host shows the committed page; only then does a whole
    /// spread report where it rests.
    var showsCommittedPage: Bool { get }

    /// Size of the prepared image the host shows for `pageID`, if any.
    func displayedImageSize(for pageID: ReaderPageID) -> CGSize?

    func pageScrollControllerDidZoom(_ controller: PageScrollController)
  }
#endif
