//
// ContentProjectionNotifier.swift
//
//

import Foundation

extension Notification.Name {
  static let bookProjectionDidChange = Notification.Name("BookProjectionDidChange")
  static let seriesProjectionDidChange = Notification.Name("SeriesProjectionDidChange")
  static let collectionProjectionDidChange = Notification.Name("CollectionProjectionDidChange")
  static let readListProjectionDidChange = Notification.Name("ReadListProjectionDidChange")
}

nonisolated enum ContentProjectionChangeReason: String, Sendable {
  case content
  case downloadStatus
  case readingProgress
}

nonisolated enum ContentProjectionNotifier {
  static let localRefreshDelay: UInt64 = 750_000_000

  @MainActor private static var activeReaderSessionID: UUID?
  @MainActor private static var pendingFlushTask: Task<Void, Never>?
  @MainActor private static var pendingBookDeadlines: [String: Date] = [:]
  @MainActor private static var pendingSeriesDeadlines: [String: Date] = [:]
  @MainActor private static var pendingCollectionDeadlines: [String: Date] = [:]
  @MainActor private static var pendingReadListDeadlines: [String: Date] = [:]
  @MainActor private static var pendingBookLibraryIds: [String: String] = [:]
  @MainActor private static var pendingSeriesLibraryIds: [String: String] = [:]
  @MainActor private static var pendingBookReasons: [String: Set<ContentProjectionChangeReason>] = [:]
  @MainActor private static var pendingSeriesReasons: [String: Set<ContentProjectionChangeReason>] = [:]
  @MainActor private static var pendingAllSeriesDeadline: Date?
  @MainActor private static var pendingAllSeriesReasons: Set<ContentProjectionChangeReason> = []

  @MainActor
  static func readerDidOpen(sessionID: UUID) {
    activeReaderSessionID = sessionID
    pendingFlushTask?.cancel()
    pendingFlushTask = nil
  }

  @MainActor
  static func readerDidClose(sessionID: UUID) {
    guard activeReaderSessionID == sessionID else { return }
    activeReaderSessionID = nil
    schedulePendingFlush()
  }

  static func postBookDidChange(
    bookId: String,
    libraryId: String? = nil,
    reason: ContentProjectionChangeReason = .content,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    guard !bookId.isEmpty else { return }

    await enqueueBookIds([bookId], libraryId: libraryId, reason: reason, refreshDelay: refreshDelay)
  }

  static func postBooksDidChange(
    bookIds: [String],
    libraryId: String? = nil,
    reason: ContentProjectionChangeReason = .content,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    let ids = Set(bookIds.filter { !$0.isEmpty })
    guard !ids.isEmpty else { return }

    await enqueueBookIds(ids, libraryId: libraryId, reason: reason, refreshDelay: refreshDelay)
  }

  static func postSeriesDidChange(
    seriesId: String,
    libraryId: String? = nil,
    reason: ContentProjectionChangeReason = .content,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    guard !seriesId.isEmpty else { return }

    let resolvedLibraryId = await resolveSeriesLibraryId(seriesId: seriesId, libraryId: libraryId)
    await enqueueSeriesIds([seriesId], libraryId: resolvedLibraryId, reason: reason, refreshDelay: refreshDelay)
  }

  static func postAllSeriesDidChange(
    reason: ContentProjectionChangeReason = .content,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    await enqueueAllSeries(reason: reason, refreshDelay: refreshDelay)
  }

  static func postCollectionDidChange(
    collectionId: String,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    guard !collectionId.isEmpty else { return }

    await enqueueCollectionIds([collectionId], refreshDelay: refreshDelay)
  }

  static func postCollectionsDidChange(
    collectionIds: [String],
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    let ids = Set(collectionIds.filter { !$0.isEmpty })
    guard !ids.isEmpty else { return }

    await enqueueCollectionIds(ids, refreshDelay: refreshDelay)
  }

  static func postReadListDidChange(
    readListId: String,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    guard !readListId.isEmpty else { return }

    await enqueueReadListIds([readListId], refreshDelay: refreshDelay)
  }

  static func postReadListsDidChange(
    readListIds: [String],
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    let ids = Set(readListIds.filter { !$0.isEmpty })
    guard !ids.isEmpty else { return }

    await enqueueReadListIds(ids, refreshDelay: refreshDelay)
  }

  static func postBookAndSeriesDidChange(
    bookId: String,
    seriesId: String? = nil,
    libraryId: String? = nil,
    reason: ContentProjectionChangeReason = .content,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    await postBookAndSeriesDidChange(
      bookId: bookId,
      instanceId: AppConfig.current.instanceId,
      seriesId: seriesId,
      libraryId: libraryId,
      reason: reason,
      refreshDelay: refreshDelay
    )
  }

  static func postBookAndSeriesDidChange(
    bookId: String,
    instanceId: String,
    seriesId: String? = nil,
    libraryId: String? = nil,
    reason: ContentProjectionChangeReason = .content,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    guard !bookId.isEmpty else { return }

    if let seriesId {
      let resolvedLibraryId = await resolveSeriesLibraryId(
        seriesId: seriesId,
        instanceId: instanceId,
        libraryId: libraryId
      )
      await postBookDidChange(
        bookId: bookId,
        libraryId: resolvedLibraryId,
        reason: reason,
        refreshDelay: refreshDelay
      )
      await postSeriesDidChange(
        seriesId: seriesId,
        libraryId: resolvedLibraryId,
        reason: reason,
        refreshDelay: refreshDelay
      )
      return
    }

    guard let scope = await fetchBookProjectionScope(forBookId: bookId, instanceId: instanceId) else {
      await postBookDidChange(
        bookId: bookId,
        libraryId: libraryId,
        reason: reason,
        refreshDelay: refreshDelay
      )
      await postAllSeriesDidChange(reason: reason, refreshDelay: refreshDelay)
      return
    }

    let resolvedLibraryId = libraryId ?? scope.libraryId
    await postBookDidChange(
      bookId: bookId,
      libraryId: resolvedLibraryId,
      reason: reason,
      refreshDelay: refreshDelay
    )
    await postSeriesDidChange(
      seriesId: scope.seriesId,
      libraryId: resolvedLibraryId,
      reason: reason,
      refreshDelay: refreshDelay
    )
  }

  static func postBooksAndSeriesDidChange(
    bookIds: [String],
    instanceId: String,
    reason: ContentProjectionChangeReason = .content,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    let ids = Set(bookIds.filter { !$0.isEmpty })
    guard !ids.isEmpty else { return }

    let bookScopes = await fetchBookProjectionScopes(forBookIds: Array(ids), instanceId: instanceId)
    let bookIdsByLibraryId = Dictionary(grouping: ids) { bookId in
      bookScopes[bookId]?.libraryId
    }
    for (libraryId, scopedBookIds) in bookIdsByLibraryId {
      await postBooksDidChange(
        bookIds: Array(scopedBookIds),
        libraryId: libraryId,
        reason: reason,
        refreshDelay: refreshDelay
      )
    }

    var seriesScopes: [String: String] = [:]
    for scope in bookScopes.values {
      seriesScopes[scope.seriesId] = scope.libraryId
    }
    for (seriesId, libraryId) in seriesScopes {
      await postSeriesDidChange(
        seriesId: seriesId,
        libraryId: libraryId,
        reason: reason,
        refreshDelay: refreshDelay
      )
    }
    if bookScopes.count < ids.count {
      await postAllSeriesDidChange(reason: reason, refreshDelay: refreshDelay)
    }
  }

  static func postSeriesBooksDidChange(
    seriesId: String,
    reason: ContentProjectionChangeReason = .content,
    refreshDelay: UInt64 = localRefreshDelay
  ) async {
    guard !seriesId.isEmpty else { return }

    let bookIds = await fetchSeriesBookIds(seriesId: seriesId)
    let libraryId = await fetchSeriesLibraryId(seriesId: seriesId)
    await postBooksDidChange(
      bookIds: bookIds,
      libraryId: libraryId,
      reason: reason,
      refreshDelay: refreshDelay
    )
    await postSeriesDidChange(
      seriesId: seriesId,
      libraryId: libraryId,
      reason: reason,
      refreshDelay: refreshDelay
    )
  }

  static func changeReasons(from notification: Notification) -> Set<ContentProjectionChangeReason> {
    guard let userInfo = notification.userInfo else { return [.content] }

    if let reasons = userInfo["changeReasons"] as? Set<String> {
      return parsedChangeReasons(from: reasons)
    }
    if let reasons = userInfo["changeReasons"] as? [String] {
      return parsedChangeReasons(from: Set(reasons))
    }
    if let reason = userInfo["changeReason"] as? String {
      return parsedChangeReasons(from: [reason])
    }
    return [.content]
  }

  static func bookIds(from notification: Notification) -> Set<String> {
    if let ids = notification.userInfo?["bookIds"] as? Set<String> {
      return ids
    }
    if let ids = notification.userInfo?["bookIds"] as? [String] {
      return Set(ids)
    }
    if let id = notification.userInfo?["bookId"] as? String {
      return [id]
    }
    return []
  }

  static func seriesIds(from notification: Notification) -> Set<String> {
    if let ids = notification.userInfo?["seriesIds"] as? Set<String> {
      return ids
    }
    if let ids = notification.userInfo?["seriesIds"] as? [String] {
      return Set(ids)
    }
    if let id = notification.userInfo?["seriesId"] as? String {
      return [id]
    }
    return []
  }

  private static func parsedChangeReasons(from rawValues: Set<String>) -> Set<ContentProjectionChangeReason> {
    var reasons = Set(rawValues.compactMap(ContentProjectionChangeReason.init(rawValue:)))
    if reasons.count != rawValues.count {
      reasons.insert(.content)
    }
    return reasons.isEmpty ? [.content] : reasons
  }

  private static func fetchBookProjectionScope(
    forBookId bookId: String,
    instanceId: String
  ) async -> (seriesId: String, libraryId: String)? {
    guard
      let database = try? await DatabaseOperator.database(),
      let item = try? await database.fetchBookDisplayItem(
        bookId: bookId,
        instanceId: instanceId
      )
    else { return nil }

    return (seriesId: item.book.seriesId, libraryId: item.book.libraryId)
  }

  private static func fetchBookProjectionScopes(
    forBookIds bookIds: [String],
    instanceId: String
  ) async -> [String: (seriesId: String, libraryId: String)] {
    var scopes: [String: (seriesId: String, libraryId: String)] = [:]
    for bookId in Set(bookIds) {
      if let scope = await fetchBookProjectionScope(forBookId: bookId, instanceId: instanceId) {
        scopes[bookId] = scope
      }
    }

    return scopes
  }

  private static func fetchSeriesLibraryId(
    seriesId: String,
    instanceId: String = AppConfig.current.instanceId
  ) async -> String? {
    guard
      let database = try? await DatabaseOperator.database(),
      let item = try? await database.fetchSeriesDisplayItem(
        seriesId: seriesId,
        instanceId: instanceId
      )
    else { return nil }

    return item.series.libraryId
  }

  private static func resolveSeriesLibraryId(
    seriesId: String,
    instanceId: String = AppConfig.current.instanceId,
    libraryId: String?
  ) async -> String? {
    if let libraryId {
      return libraryId
    }
    return await fetchSeriesLibraryId(seriesId: seriesId, instanceId: instanceId)
  }

  private static func fetchSeriesBookIds(seriesId: String) async -> [String] {
    guard let database = try? await DatabaseOperator.database() else { return [] }

    let pageSize = 500
    var page = 0
    var ids: [String] = []

    while true {
      let pageIds = await database.fetchSeriesBookIds(
        seriesId: seriesId,
        browseOpts: BookBrowseOptions(),
        page: page,
        size: pageSize
      )
      ids.append(contentsOf: pageIds)

      guard pageIds.count == pageSize else { break }
      page += 1
    }

    return ids
  }

  @MainActor
  private static func enqueueBookIds<S: Sequence>(
    _ ids: S,
    libraryId: String?,
    reason: ContentProjectionChangeReason,
    refreshDelay: UInt64
  )
  where S.Element == String {
    let deadline = deadline(after: refreshDelay)
    for id in ids where !id.isEmpty {
      mergeDeadline(deadline, for: id, into: &pendingBookDeadlines)
      mergeLibraryId(libraryId, for: id, into: &pendingBookLibraryIds)
      mergeReason(reason, for: id, into: &pendingBookReasons)
    }
    schedulePendingFlush()
  }

  @MainActor
  private static func enqueueSeriesIds<S: Sequence>(
    _ ids: S,
    libraryId: String?,
    reason: ContentProjectionChangeReason,
    refreshDelay: UInt64
  )
  where S.Element == String {
    let deadline = deadline(after: refreshDelay)
    for id in ids where !id.isEmpty {
      mergeDeadline(deadline, for: id, into: &pendingSeriesDeadlines)
      mergeLibraryId(libraryId, for: id, into: &pendingSeriesLibraryIds)
      mergeReason(reason, for: id, into: &pendingSeriesReasons)
    }
    schedulePendingFlush()
  }

  @MainActor
  private static func enqueueAllSeries(reason: ContentProjectionChangeReason, refreshDelay: UInt64) {
    let deadline = deadline(after: refreshDelay)
    if let existing = pendingAllSeriesDeadline {
      pendingAllSeriesDeadline = min(existing, deadline)
    } else {
      pendingAllSeriesDeadline = deadline
    }
    pendingAllSeriesReasons.insert(reason)
    schedulePendingFlush()
  }

  @MainActor
  private static func enqueueCollectionIds<S: Sequence>(_ ids: S, refreshDelay: UInt64)
  where S.Element == String {
    let deadline = deadline(after: refreshDelay)
    for id in ids where !id.isEmpty {
      mergeDeadline(deadline, for: id, into: &pendingCollectionDeadlines)
    }
    schedulePendingFlush()
  }

  @MainActor
  private static func enqueueReadListIds<S: Sequence>(_ ids: S, refreshDelay: UInt64)
  where S.Element == String {
    let deadline = deadline(after: refreshDelay)
    for id in ids where !id.isEmpty {
      mergeDeadline(deadline, for: id, into: &pendingReadListDeadlines)
    }
    schedulePendingFlush()
  }

  @MainActor
  private static func schedulePendingFlush() {
    pendingFlushTask?.cancel()
    pendingFlushTask = nil

    guard activeReaderSessionID == nil, let deadline = nextPendingDeadline() else { return }

    let sleepNanoseconds = sleepNanoseconds(until: deadline)
    pendingFlushTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: sleepNanoseconds)
      } catch {
        return
      }

      guard !Task.isCancelled else { return }
      flushDueChanges()
    }
  }

  @MainActor
  private static func flushDueChanges() {
    pendingFlushTask = nil

    guard activeReaderSessionID == nil else { return }

    let now = Date()
    let bookIds = takeDueIds(from: &pendingBookDeadlines, now: now)
    let allSeriesReasons = takeAllSeriesIfDue(now: now)
    let seriesIds = allSeriesReasons == nil ? takeDueIds(from: &pendingSeriesDeadlines, now: now) : []
    let collectionIds = takeDueIds(from: &pendingCollectionDeadlines, now: now)
    let readListIds = takeDueIds(from: &pendingReadListDeadlines, now: now)

    if !bookIds.isEmpty {
      let libraryIds = takeCompleteLibraryIds(for: bookIds, from: &pendingBookLibraryIds)
      let reasons = takeReasons(for: bookIds, from: &pendingBookReasons)
      postBooksNow(bookIds, libraryIds: libraryIds, reasons: reasons)
    }
    if let allSeriesReasons {
      pendingSeriesDeadlines.removeAll()
      pendingSeriesLibraryIds.removeAll()
      pendingSeriesReasons.removeAll()
      postAllSeriesNow(reasons: allSeriesReasons)
    } else if !seriesIds.isEmpty {
      let libraryIds = takeCompleteLibraryIds(for: seriesIds, from: &pendingSeriesLibraryIds)
      let reasons = takeReasons(for: seriesIds, from: &pendingSeriesReasons)
      postSeriesNow(seriesIds, libraryIds: libraryIds, reasons: reasons)
    }
    for collectionId in collectionIds {
      postCollectionNow(collectionId)
    }
    for readListId in readListIds {
      postReadListNow(readListId)
    }
    schedulePendingFlush()
  }

  @MainActor
  private static func nextPendingDeadline() -> Date? {
    [
      pendingBookDeadlines.values.min(),
      pendingSeriesDeadlines.values.min(),
      pendingCollectionDeadlines.values.min(),
      pendingReadListDeadlines.values.min(),
      pendingAllSeriesDeadline,
    ]
    .compactMap { $0 }
    .min()
  }

  private static func deadline(after refreshDelay: UInt64) -> Date {
    Date().addingTimeInterval(Double(refreshDelay) / 1_000_000_000)
  }

  private static func sleepNanoseconds(until deadline: Date) -> UInt64 {
    let seconds = max(0, deadline.timeIntervalSinceNow)
    return UInt64(seconds * 1_000_000_000)
  }

  private static func mergeDeadline(_ deadline: Date, for id: String, into deadlines: inout [String: Date]) {
    if let existing = deadlines[id] {
      deadlines[id] = min(existing, deadline)
    } else {
      deadlines[id] = deadline
    }
  }

  private static func mergeLibraryId(_ libraryId: String?, for id: String, into libraryIds: inout [String: String]) {
    guard let libraryId, !libraryId.isEmpty else { return }
    libraryIds[id] = libraryId
  }

  private static func mergeReason(
    _ reason: ContentProjectionChangeReason,
    for id: String,
    into reasons: inout [String: Set<ContentProjectionChangeReason>]
  ) {
    reasons[id, default: []].insert(reason)
  }

  private static func takeDueIds(from deadlines: inout [String: Date], now: Date) -> Set<String> {
    let ids = deadlines.compactMap { id, deadline in
      deadline <= now ? id : nil
    }
    for id in ids {
      deadlines.removeValue(forKey: id)
    }
    return Set(ids)
  }

  @MainActor
  private static func takeAllSeriesIfDue(now: Date) -> Set<ContentProjectionChangeReason>? {
    guard let deadline = pendingAllSeriesDeadline, deadline <= now else { return nil }
    pendingAllSeriesDeadline = nil
    let reasons = pendingAllSeriesReasons
    pendingAllSeriesReasons.removeAll()
    return reasons.isEmpty ? [.content] : reasons
  }

  private static func takeReasons(
    for ids: Set<String>,
    from reasons: inout [String: Set<ContentProjectionChangeReason>]
  ) -> Set<ContentProjectionChangeReason> {
    var result = Set<ContentProjectionChangeReason>()
    for id in ids {
      if let idReasons = reasons.removeValue(forKey: id) {
        result.formUnion(idReasons)
      }
    }
    return result.isEmpty ? [.content] : result
  }

  private static func takeCompleteLibraryIds(for ids: Set<String>, from libraryIds: inout [String: String])
    -> Set<String>?
  {
    var result = Set<String>()
    var hasUnscopedId = false
    for id in ids {
      if let libraryId = libraryIds.removeValue(forKey: id) {
        result.insert(libraryId)
      } else {
        hasUnscopedId = true
      }
    }
    guard !hasUnscopedId else { return nil }
    return result
  }

  @MainActor
  private static func postBooksNow(
    _ ids: Set<String>,
    libraryIds: Set<String>?,
    reasons: Set<ContentProjectionChangeReason>
  ) {
    var userInfo: [AnyHashable: Any] = ["bookIds": ids]
    if ids.count == 1, let bookId = ids.first {
      userInfo["bookId"] = bookId
    }
    addLibraryScope(libraryIds, to: &userInfo)
    addChangeReasons(reasons, to: &userInfo)
    NotificationCenter.default.post(
      name: .bookProjectionDidChange,
      object: nil,
      userInfo: userInfo
    )
  }

  @MainActor
  private static func postSeriesNow(
    _ ids: Set<String>,
    libraryIds: Set<String>?,
    reasons: Set<ContentProjectionChangeReason>
  ) {
    var userInfo: [AnyHashable: Any] = ["seriesIds": ids]
    if ids.count == 1, let seriesId = ids.first {
      userInfo["seriesId"] = seriesId
    }
    addLibraryScope(libraryIds, to: &userInfo)
    addChangeReasons(reasons, to: &userInfo)
    NotificationCenter.default.post(
      name: .seriesProjectionDidChange,
      object: nil,
      userInfo: userInfo
    )
  }

  @MainActor
  private static func postAllSeriesNow(reasons: Set<ContentProjectionChangeReason>) {
    var userInfo: [AnyHashable: Any] = ["allSeries": true]
    addChangeReasons(reasons, to: &userInfo)
    NotificationCenter.default.post(
      name: .seriesProjectionDidChange,
      object: nil,
      userInfo: userInfo
    )
  }

  @MainActor
  private static func postCollectionNow(_ collectionId: String) {
    NotificationCenter.default.post(
      name: .collectionProjectionDidChange,
      object: nil,
      userInfo: ["collectionId": collectionId]
    )
  }

  @MainActor
  private static func postReadListNow(_ readListId: String) {
    NotificationCenter.default.post(
      name: .readListProjectionDidChange,
      object: nil,
      userInfo: ["readListId": readListId]
    )
  }

  private static func addLibraryScope(_ libraryIds: Set<String>?, to userInfo: inout [AnyHashable: Any]) {
    guard let libraryIds else { return }
    guard !libraryIds.isEmpty else { return }
    userInfo["libraryIds"] = libraryIds
    if libraryIds.count == 1, let libraryId = libraryIds.first {
      userInfo["libraryId"] = libraryId
    }
  }

  private static func addChangeReasons(
    _ reasons: Set<ContentProjectionChangeReason>,
    to userInfo: inout [AnyHashable: Any]
  ) {
    let rawReasons = Set(reasons.map(\.rawValue))
    guard !rawReasons.isEmpty else { return }
    userInfo["changeReasons"] = rawReasons
    if rawReasons.count == 1, let reason = rawReasons.first {
      userInfo["changeReason"] = reason
    }
  }
}
