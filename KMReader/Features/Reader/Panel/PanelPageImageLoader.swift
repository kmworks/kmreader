//
// PanelPageImageLoader.swift
//
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor PanelPageImageLoader {
    private let imageCache = ImageCache()

    func pageImage(bookId: String, page: BookPage) async -> CGImage? {
        guard let fileURL = await resolvedFileURL(bookId: bookId, page: page) else { return nil }
        return await Self.decodeCGImage(at: fileURL)
    }

    // MARK: - Private

    private func resolvedFileURL(bookId: String, page: BookPage) async -> URL? {
        // 1. Offline downloaded content
        if let offlineURL = try? await OfflineManager.shared.getOfflinePageImageURL(
            instanceId: AppConfig.current.instanceId,
            bookId: bookId,
            page: page
        ) {
            return offlineURL
        }

        // 2. Disk cache hit (shares namespace with reader's own ImageCache)
        if await imageCache.hasImage(bookId: bookId, page: page) {
            return imageCache.imageFileURL(bookId: bookId, page: page)
        }

        // 3. Network fetch – skipped when offline
        guard !AppConfig.isOffline else { return nil }
        guard let remoteURL = await resolvedDownloadURL(for: page, bookId: bookId) else { return nil }

        do {
            let result = try await BookService.downloadImageResource(at: remoteURL)
            await imageCache.storeImageData(result.data, bookId: bookId, page: page)
            guard await imageCache.hasImage(bookId: bookId, page: page) else { return nil }
            return imageCache.imageFileURL(bookId: bookId, page: page)
        } catch {
            return nil
        }
    }

    private func resolvedDownloadURL(for page: BookPage, bookId: String) async -> URL? {
        if let url = page.downloadURL { return url }
        return BookService.getBookPageURL(bookId: bookId, page: page.number)
    }

    // Runs detached so the CGImageSource decode never blocks the main thread or the actor.
    private static func decodeCGImage(at fileURL: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }.value
    }
}
