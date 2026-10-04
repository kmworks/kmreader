//
// LibraryFormSections.swift
//
//

import SwiftUI

/// Tabbed form sections of the library add/edit sheets: a segmented tab picker
/// on iOS/macOS, stacked sections on tvOS.
struct LibraryFormSections<Fields: LibraryFormFields>: View {
  @Binding var fields: Fields
  @Binding var showDirectoryBrowser: Bool

  @State private var selectedTab = 0
  // Hoisted above the tab switch so half-typed input survives it.
  @State private var newExclusion = ""

  var body: some View {
    #if os(tvOS)
      LibraryFormGeneralSection(fields: $fields, showDirectoryBrowser: $showDirectoryBrowser)
      LibraryFormScannerSection(fields: $fields, newExclusion: $newExclusion)
      LibraryFormOptionsSection(fields: $fields)
      LibraryFormMetadataSection(fields: $fields)
    #else
      Picker("", selection: $selectedTab) {
        Text(String(localized: "library.add.tab.general", defaultValue: "General")).tag(0)
        Text(String(localized: "library.add.tab.scanner", defaultValue: "Scanner")).tag(1)
        Text(String(localized: "library.add.tab.options", defaultValue: "Options")).tag(2)
        Text(String(localized: "library.add.tab.metadata", defaultValue: "Metadata")).tag(3)
      }
      .pickerStyle(.segmented)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      switch selectedTab {
      case 0:
        LibraryFormGeneralSection(fields: $fields, showDirectoryBrowser: $showDirectoryBrowser)
      case 1:
        LibraryFormScannerSection(fields: $fields, newExclusion: $newExclusion)
      case 2:
        LibraryFormOptionsSection(fields: $fields)
      case 3:
        LibraryFormMetadataSection(fields: $fields)
      default:
        EmptyView()
      }
    #endif
  }
}
