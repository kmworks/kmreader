//
// LibraryBrowseView.swift
//
//

import SwiftUI

/// iPhone Library tab root: content-first browsing (Apple Books style) over the
/// global library selection (dashboard.libraryIds, shared with Home).
/// Library management stays in Settings.
struct LibraryBrowseView: View {
  let authViewModel: AuthViewModel

  var body: some View {
    BrowseView(authViewModel: authViewModel, libraryTab: true)
  }
}
