//
// ImageShareHelper.swift
//
//

import SwiftUI

#if os(iOS)
  import LinkPresentation
  import UIKit

  // Custom activity item source to provide image preview in share sheet
  final class ImageActivityItemSource: NSObject, UIActivityItemSource {
    let image: UIImage
    let fileName: String?

    init(image: UIImage, fileName: String? = nil) {
      self.image = image
      self.fileName = fileName
      super.init()
    }

    func activityViewControllerPlaceholderItem(
      _ activityViewController: UIActivityViewController
    ) -> Any {
      return image
    }

    func activityViewController(
      _ activityViewController: UIActivityViewController,
      itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
      return image
    }

    func activityViewControllerLinkMetadata(
      _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
      let metadata = LPLinkMetadata()
      let displayName = fileName.map { ($0 as NSString).lastPathComponent } ?? String(localized: "Image")
      metadata.title = displayName
      metadata.imageProvider = NSItemProvider(object: image)
      return metadata
    }
  }

  enum ImageShareHelper {
    static func share(image: UIImage, fileName: String? = nil) {
      shareMultiple(images: [image], fileNames: fileName.map { [$0] } ?? [])
    }

    static func shareMultiple(images: [UIImage], fileNames: [String]) {
      let items: [Any] = images.enumerated().map { index, image in
        let name = index < fileNames.count ? fileNames[index] : nil
        return ImageActivityItemSource(image: image, fileName: name)
      }
      ShareHelper.share(items: items)
    }
  }

#elseif os(macOS)
  import AppKit

  enum ImageShareHelper {
    static func share(image: NSImage, fileName: String? = nil) {
      shareMultiple(images: [image], fileNames: fileName.map { [$0] } ?? [])
    }

    static func shareMultiple(images: [NSImage], fileNames: [String]) {
      let items: [Any] = images.enumerated().compactMap { index, image in
        let name = index < fileNames.count ? fileNames[index] : nil
        return createTempImageFile(image: image, fileName: name) ?? image
      }
      ShareHelper.share(items: items)
    }

    private static func createTempImageFile(image: NSImage, fileName: String?) -> URL? {
      guard let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
      else { return nil }

      let tempDir = FileManager.default.temporaryDirectory
      let baseName = fileName.map { ($0 as NSString).lastPathComponent } ?? "shared_image_\(UUID().uuidString)"
      let fileURL = tempDir.appendingPathComponent(baseName).appendingPathExtension("png")

      do {
        try pngData.write(to: fileURL)
        return fileURL
      } catch {
        print("Failed to write temporary image for sharing: \(error)")
        return nil
      }
    }
  }
#endif
