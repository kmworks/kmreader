import Foundation

nonisolated struct MangaTARArchive {
  enum ArchiveError: Error {
    case truncated
    case invalidHeader
    case invalidChecksum
    case unsafePath
    case unsupportedEntry
    case tooManyEntries
  }

  static func extract(_ archiveURL: URL, to destination: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    let input = try FileHandle(forReadingFrom: archiveURL)
    defer { try? input.close() }
    var entries = 0

    while true {
      let header = input.readData(ofLength: 512)
      if header.isEmpty { return }
      guard header.count == 512 else { throw ArchiveError.truncated }
      if header.allSatisfy({ $0 == 0 }) { return }

      let storedChecksum = try octal(header, range: 148..<156)
      let actualChecksum = header.enumerated().reduce(0) {
        $0 + ($1.offset >= 148 && $1.offset < 156 ? 32 : Int($1.element))
      }
      guard storedChecksum == actualChecksum else { throw ArchiveError.invalidChecksum }
      guard Data(header[257...261]) == Data("ustar".utf8) else { throw ArchiveError.invalidHeader }

      let size = try octal(header, range: 124..<136)
      guard size >= 0 else { throw ArchiveError.invalidHeader }
      let type = header[156]
      let rawPath = try string(header, range: 0..<100)
      let path = rawPath.hasSuffix("/") ? String(rawPath.dropLast()) : rawPath
      guard isSafe(path: path) else { throw ArchiveError.unsafePath }
      entries += 1
      guard entries <= 100 else { throw ArchiveError.tooManyEntries }

      if type == 53 {
        try fileManager.createDirectory(
          at: destination.appendingPathComponent(path),
          withIntermediateDirectories: true
        )
        try copyContent(from: input, to: nil, count: size)
      } else if type == 0 || type == 48 {
        let fileURL = destination.appendingPathComponent(path)
        try fileManager.createDirectory(
          at: fileURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: fileURL)
        defer { try? output.close() }
        try output.truncate(atOffset: 0)
        try copyContent(from: input, to: output, count: size)
      } else {
        throw ArchiveError.unsupportedEntry
      }

      let padding = (512 - size % 512) % 512
      _ = try readExactly(input, count: padding)
    }
  }

  private static func copyContent(
    from input: FileHandle,
    to output: FileHandle?,
    count: Int
  ) throws {
    var remaining = count
    while remaining > 0 {
      let chunk = try readExactly(input, count: min(1024 * 1024, remaining))
      output?.write(chunk)
      remaining -= chunk.count
    }
  }

  private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
    let data = handle.readData(ofLength: count)
    guard data.count == count else { throw ArchiveError.truncated }
    return data
  }

  private static func octal(_ data: Data, range: Range<Int>) throws -> Int {
    let text = try string(data, range: range)
    guard let value = Int(text, radix: 8) else { throw ArchiveError.invalidHeader }
    return value
  }

  private static func string(_ data: Data, range: Range<Int>) throws -> String {
    let bytes = data.subdata(in: range).prefix { $0 != 0 && $0 != 32 }
    guard let text = String(bytes: bytes, encoding: .utf8), !text.isEmpty else {
      throw ArchiveError.invalidHeader
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isSafe(path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains("..") && !components.contains("")
  }
}
