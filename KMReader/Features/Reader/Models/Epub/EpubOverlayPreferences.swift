//
// EpubOverlayPreferences.swift
//
//

import Foundation

nonisolated struct EpubOverlayPreferences: RawRepresentable, Equatable, Sendable {
  typealias RawValue = String

  var readerHeaderLeading: EpubOverlayTextItem
  var readerHeaderCenter: EpubOverlayTextItem
  var readerHeaderTrailing: EpubOverlayTextItem
  var readerFooterLeading: EpubOverlayTextItem
  var readerFooterCenter: EpubOverlayTextItem
  var readerFooterTrailing: EpubOverlayTextItem
  var showsReaderProgressBar: Bool
  var controlsHeaderCenter: EpubOverlayTextItem
  var controlsFooterCenter: EpubOverlayTextItem

  init() {
    readerHeaderLeading = .none
    readerHeaderCenter = .bookTitle
    readerHeaderTrailing = .none
    readerFooterLeading = .chapterTitle
    readerFooterCenter = .none
    readerFooterTrailing = .chapterRemaining
    showsReaderProgressBar = false
    controlsHeaderCenter = .bookProgressPercent
    controlsFooterCenter = .chapterPosition
  }

  init?(rawValue: String) {
    guard !rawValue.isEmpty else {
      self.init()
      return
    }

    guard let data = rawValue.data(using: .utf8),
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      self.init()
      return
    }

    self.init()
    readerHeaderLeading = Self.textItem(dict["readerHeaderLeading"], default: readerHeaderLeading)
    readerHeaderCenter = Self.textItem(dict["readerHeaderCenter"], default: readerHeaderCenter)
    readerHeaderTrailing = Self.textItem(dict["readerHeaderTrailing"], default: readerHeaderTrailing)
    readerFooterLeading = Self.textItem(dict["readerFooterLeading"], default: readerFooterLeading)
    readerFooterCenter = Self.textItem(dict["readerFooterCenter"], default: readerFooterCenter)
    readerFooterTrailing = Self.textItem(dict["readerFooterTrailing"], default: readerFooterTrailing)
    showsReaderProgressBar = Self.bool(dict["showsReaderProgressBar"], default: showsReaderProgressBar)
    controlsHeaderCenter = Self.textItem(dict["controlsHeaderCenter"], default: controlsHeaderCenter)
    controlsFooterCenter = Self.textItem(dict["controlsFooterCenter"], default: controlsFooterCenter)
  }

  var rawValue: String {
    let dict: [String: Any] = [
      "readerHeaderLeading": readerHeaderLeading.rawValue,
      "readerHeaderCenter": readerHeaderCenter.rawValue,
      "readerHeaderTrailing": readerHeaderTrailing.rawValue,
      "readerFooterLeading": readerFooterLeading.rawValue,
      "readerFooterCenter": readerFooterCenter.rawValue,
      "readerFooterTrailing": readerFooterTrailing.rawValue,
      "showsReaderProgressBar": showsReaderProgressBar,
      "controlsHeaderCenter": controlsHeaderCenter.rawValue,
      "controlsFooterCenter": controlsFooterCenter.rawValue,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    {
      return json
    }
    return "{}"
  }

  private static func textItem(_ value: Any?, default defaultValue: EpubOverlayTextItem) -> EpubOverlayTextItem {
    guard let rawValue = value as? String else { return defaultValue }
    return EpubOverlayTextItem(rawValue: rawValue) ?? defaultValue
  }

  private static func bool(_ value: Any?, default defaultValue: Bool) -> Bool {
    guard let value = value as? Bool else { return defaultValue }
    return value
  }
}
