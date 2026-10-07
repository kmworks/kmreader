//
// LibrarySelection.swift
//
//

import Foundation

struct LibrarySelection: Hashable {
  let libraryId: String
  let name: String
  let fileSize: Double?
  let booksCount: Double?
  let seriesCount: Double?
  let sidecarsCount: Double?

  init(library: KomgaLibrary) {
    libraryId = library.libraryId
    name = library.name
    fileSize = library.fileSize
    booksCount = library.booksCount
    seriesCount = library.seriesCount
    sidecarsCount = library.sidecarsCount
  }

  init(sidebarItem: SidebarLibraryItem) {
    libraryId = sidebarItem.libraryId
    name = sidebarItem.name
    fileSize = sidebarItem.fileSize
    booksCount = sidebarItem.booksCount
    seriesCount = sidebarItem.seriesCount
    sidecarsCount = sidebarItem.sidecarsCount
  }
}
