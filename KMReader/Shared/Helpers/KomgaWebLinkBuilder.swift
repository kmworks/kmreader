//
// KomgaWebLinkBuilder.swift
//
//

import Foundation

enum KomgaWebLinkBuilder {
  static func series(serverURL: String, seriesId: String) -> URL? {
    build(serverURL: serverURL, path: "/series/\(seriesId)")
  }

  static func oneshot(serverURL: String, seriesId: String) -> URL? {
    build(serverURL: serverURL, path: "/oneshot/\(seriesId)")
  }

  static func book(serverURL: String, bookId: String) -> URL? {
    build(serverURL: serverURL, path: "/book/\(bookId)")
  }

  static func collection(serverURL: String, collectionId: String) -> URL? {
    build(serverURL: serverURL, path: "/collections/\(collectionId)")
  }

  static func readList(serverURL: String, readListId: String) -> URL? {
    build(serverURL: serverURL, path: "/readlists/\(readListId)")
  }

  static func smartList(serverURL: String, smartListId: String) -> URL? {
    build(serverURL: serverURL, path: "/smart-lists/\(smartListId)")
  }

  static func bookReader(
    serverURL: String,
    bookId: String,
    pageNumber: Int?,
    incognito: Bool
  ) -> URL? {
    var queryItems = [URLQueryItem(name: "incognito", value: incognito ? "true" : "false")]
    if let pageNumber {
      queryItems.append(URLQueryItem(name: "page", value: String(pageNumber)))
    }
    return build(serverURL: serverURL, path: "/book/\(bookId)/read", queryItems: queryItems)
  }

  static func epubReader(serverURL: String, bookId: String, incognito: Bool) -> URL? {
    let queryItems = [URLQueryItem(name: "incognito", value: incognito ? "true" : "false")]
    return build(serverURL: serverURL, path: "/book/\(bookId)/read-epub", queryItems: queryItems)
  }

  private static func build(
    serverURL: String,
    path: String,
    queryItems: [URLQueryItem]? = nil
  ) -> URL? {
    let normalizedBase = Current.normalizeServerURL(serverURL)
    guard !normalizedBase.isEmpty else { return nil }
    guard var components = URLComponents(string: normalizedBase + path) else { return nil }
    if let queryItems, !queryItems.isEmpty {
      components.queryItems = queryItems
    }
    return components.url
  }
}
