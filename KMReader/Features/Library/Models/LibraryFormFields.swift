//
// LibraryFormFields.swift
//
//

import Foundation

/// Field set shared by the library create/edit request bodies, so the add and
/// edit sheets render the same form sections.
protocol LibraryFormFields {
  var name: String { get set }
  var root: String { get set }

  var emptyTrashAfterScan: Bool { get set }
  var scanForceModifiedTime: Bool { get set }
  var scanOnStartup: Bool { get set }
  var scanInterval: ScanInterval { get set }
  var scanCbx: Bool { get set }
  var scanPdf: Bool { get set }
  var scanEpub: Bool { get set }
  var scanDirectoryExclusions: [String] { get set }
  var oneshotsDirectory: String { get set }

  var hashFiles: Bool { get set }
  var hashPages: Bool { get set }
  var hashKoreader: Bool { get set }
  var analyzeDimensions: Bool { get set }
  var repairExtensions: Bool { get set }
  var convertToCbz: Bool { get set }
  var seriesCover: SeriesCoverMode { get set }

  var importComicInfoBook: Bool { get set }
  var importComicInfoSeries: Bool { get set }
  var importComicInfoCollection: Bool { get set }
  var importComicInfoReadList: Bool { get set }
  var importComicInfoSeriesAppendVolume: Bool { get set }
  var importEpubBook: Bool { get set }
  var importEpubSeries: Bool { get set }
  var importMylarSeries: Bool { get set }
  var importLocalArtwork: Bool { get set }
  var importBarcodeIsbn: Bool { get set }
}

extension LibraryCreation: LibraryFormFields {}
extension LibraryUpdate: LibraryFormFields {}
