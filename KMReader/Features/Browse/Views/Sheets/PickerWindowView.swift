//
// PickerWindowView.swift
//
//

#if os(macOS)
  import SwiftUI

  /// Root view of the standalone picker window on macOS. Hosts the same
  /// picker sheets used on other platforms; the mutation and the refresh
  /// notifications are centralized here because call-site closures cannot
  /// reach into a separate window.
  struct PickerWindowView: View {
    let request: PickerWindowRequest

    var body: some View {
      switch request {
      case .readList(let bookId):
        ReadListPickerSheet(bookIds: [bookId]) { readListId in
          Task {
            await addBook(bookId, toReadList: readListId)
          }
        }
      case .collection(let seriesId):
        CollectionPickerSheet(seriesIds: [seriesId]) { collectionId in
          Task {
            await addSeries(seriesId, toCollection: collectionId)
          }
        }
      }
    }

    private func addBook(_ bookId: String, toReadList readListId: String) async {
      do {
        try await ReadListService.addBooksToReadList(
          readListId: readListId,
          bookIds: [bookId]
        )
        // Sync so the local membership reflects the change immediately.
        _ = try? await SyncService.syncReadList(id: readListId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.book.booksAddedToReadList"))
        await ContentProjectionNotifier.postReadListDidChange(readListId: readListId)
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }

    private func addSeries(_ seriesId: String, toCollection collectionId: String) async {
      do {
        try await CollectionService.addSeriesToCollection(
          collectionId: collectionId,
          seriesIds: [seriesId]
        )
        // Sync so the local membership reflects the change immediately.
        _ = try? await SyncService.syncCollection(id: collectionId)
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.addedToCollection"))
        await ContentProjectionNotifier.postCollectionDidChange(collectionId: collectionId)
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
#endif
