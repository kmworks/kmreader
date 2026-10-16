#if os(iOS) || os(macOS)
  import Foundation
  import PDFKit

  extension PdfReaderViewModel {
    func search(text: String) async {
      let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if query.isEmpty {
        searchResults = []
        isSearching = false
        return
      }

      guard let documentURL else {
        searchResults = []
        isSearching = false
        return
      }

      isSearching = true
      searchResults = []

      guard let document = PDFDocument(url: documentURL) else {
        isSearching = false
        return
      }

      var results: [PdfSearchResult] = []
      let pageCount = document.pageCount

      for index in 0..<pageCount {
        guard let page = document.page(at: index), let text = page.string else {
          if index.isMultiple(of: 10) {
            await Task.yield()
          }
          continue
        }

        guard
          let matchRange = text.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
          )
        else {
          if index.isMultiple(of: 10) {
            await Task.yield()
          }
          continue
        }

        let snippet = buildSnippet(from: text, matchRange: matchRange)
        let pageNumber = index + 1
        results.append(
          PdfSearchResult(
            id: "\(pageNumber)-\(results.count)",
            pageNumber: pageNumber,
            snippet: snippet
          )
        )

        if results.count >= 200 {
          break
        }

        if index.isMultiple(of: 10) {
          await Task.yield()
        }
      }

      searchResults = results
      isSearching = false
    }

    private func buildSnippet(from text: String, matchRange: Range<String.Index>) -> String {
      let lowerBound =
        text.index(matchRange.lowerBound, offsetBy: -40, limitedBy: text.startIndex)
        ?? text.startIndex
      let upperBound =
        text.index(matchRange.upperBound, offsetBy: 80, limitedBy: text.endIndex)
        ?? text.endIndex

      var snippet = String(text[lowerBound..<upperBound])
      snippet = snippet.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
      )
      snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)

      let hasLeadingEllipsis = lowerBound > text.startIndex
      let hasTrailingEllipsis = upperBound < text.endIndex

      if hasLeadingEllipsis {
        snippet = "..." + snippet
      }
      if hasTrailingEllipsis {
        snippet += "..."
      }

      return snippet
    }
  }
#endif
