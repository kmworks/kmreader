//
// FileShareHelper.swift
//
//

import SwiftUI

#if os(iOS)
  import UIKit

  enum FileShareHelper {
    static func share(url: URL) {
      guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let rootVC = windowScene.windows.first?.rootViewController
      else { return }

      var topVC = rootVC
      while let presented = topVC.presentedViewController {
        topVC = presented
      }

      let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = topVC.view
        popover.sourceRect = CGRect(
          x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }
      topVC.present(activityVC, animated: true)
    }
  }
#elseif os(macOS)
  import AppKit

  enum FileShareHelper {
    static func share(url: URL) {
      guard let contentView = NSApp.keyWindow?.contentView else { return }
      let picker = NSSharingServicePicker(items: [url])
      let rect = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
      picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
    }
  }
#endif
