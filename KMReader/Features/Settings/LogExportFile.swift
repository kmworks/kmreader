//
// LogExportFile.swift
//
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Shares every log entry matching a filter as one text file. The file is
/// written from the log store when the share is carried out, so it does not
/// depend on which rows the log list has paged in.
nonisolated struct LogExportFile: Transferable {
  let minPriority: Int
  let category: String?
  let search: String?

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .plainText) { export in
      let url = try export.makeFileURL()
      try await LogStore.shared.export(
        minPriority: export.minPriority,
        category: export.category,
        search: export.search,
        to: url
      )
      return SentTransferredFile(url)
    }
  }

  private func makeFileURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("LogExport", isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return directory.appendingPathComponent("KMReader-logs-\(formatter.string(from: Date())).txt")
  }
}
