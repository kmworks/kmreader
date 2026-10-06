//
// BrowseScopeKeys.swift
//
//

import SwiftUI

private struct BrowseLibrarySelectionKey: EnvironmentKey {
  static let defaultValue: LibrarySelection? = nil
}

private struct LibraryScopeBindingKey: EnvironmentKey {
  static let defaultValue: Binding<LibraryBrowseScope>? = nil
}

extension EnvironmentValues {
  var browseLibrarySelection: LibrarySelection? {
    get { self[BrowseLibrarySelectionKey.self] }
    set { self[BrowseLibrarySelectionKey.self] = newValue }
  }

  /// Shell-owned scope of a browse root (iPad/macOS library tabs, aggregate
  /// browse, split detail): the scope menu writes through to the shell's
  /// selection, so an in-page pick moves the sidebar/tab highlight. Pushed
  /// pages get nil and keep a page-local session scope instead.
  var libraryScopeBinding: Binding<LibraryBrowseScope>? {
    get { self[LibraryScopeBindingKey.self] }
    set { self[LibraryScopeBindingKey.self] = newValue }
  }
}
