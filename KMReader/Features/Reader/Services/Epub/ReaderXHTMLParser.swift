//
// ReaderXHTMLParser.swift
//
//

import Foundation
import SwiftSoup

enum ReaderXHTMLParser {
  static nonisolated func textLength(from data: Data, baseURL: URL) -> Int? {
    // Try different encodings to decode the data
    let encodings: [String.Encoding] = [
      .utf8,
      .utf16,
      .utf16LittleEndian,
      .utf16BigEndian,
      .isoLatin1,
      .windowsCP1252,
    ]

    for encoding in encodings {
      guard let htmlString = String(data: data, encoding: encoding) else {
        continue
      }

      do {
        let doc = try SwiftSoup.parse(htmlString, baseURL.absoluteString)
        let text = try doc.text()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          return trimmed.count
        }
      } catch {
        continue
      }
    }

    return nil
  }
}
