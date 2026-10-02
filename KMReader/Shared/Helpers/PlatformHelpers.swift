//
// PlatformHelpers.swift
//
//

import Foundation
import SwiftUI

#if os(iOS) || os(tvOS)
  import UIKit
  public typealias PlatformFont = UIFont
  public typealias PlatformImage = UIImage
  #if os(iOS)
    /// Pasteboard type for iOS platforms
    public typealias PlatformPasteboard = UIPasteboard
  #endif
#elseif os(macOS)
  import AppKit
  public typealias PlatformFont = NSFont
  public typealias PlatformImage = NSImage
  /// Pasteboard type for macOS platforms
  public typealias PlatformPasteboard = NSPasteboard
#endif

#if os(iOS) || os(tvOS)
  import Darwin
#endif

/// Platform helper for device information and UI idioms
enum PlatformHelper {

  /// Initialize cached values that require MainActor
  @MainActor
  static func setup() {
    // 1. Detect device model
    let detectedModel = machineIdentifier

    // 2. Detect OS version
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let detectedOS = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

    // 3. Set User-Agent
    let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "KMReader"
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    #if os(iOS)
      let platform = "iOS"
    #elseif os(macOS)
      let platform = "macOS"
    #elseif os(tvOS)
      let platform = "tvOS"
    #else
      let platform = "Unknown"
    #endif

    AppConfig.userAgent =
      "\(appName)/\(appVersion) (\(detectedModel); \(platform) \(detectedOS); Build \(buildNumber))"

    // 4. Handle device identifier
    let storedId = AppConfig.deviceIdentifier
    if storedId.isEmpty {
      var newId: String?
      #if os(iOS)
        newId = UIDevice.current.identifierForVendor?.uuidString
      #endif
      let finalId = newId ?? UUID().uuidString
      AppConfig.deviceIdentifier = finalId
    }
  }

  /// Check if running on iPad
  @MainActor
  static var isPad: Bool {
    #if os(iOS)
      return UIDevice.current.userInterfaceIdiom == .pad
    #else
      return false
    #endif
  }

  /// Darwin machine identifier (e.g. "iPhone18,1"), stable across OS
  /// releases and usable without any entitlement.
  static var machineIdentifier: String {
    #if os(iOS) || os(tvOS)
      var systemInfo = utsname()
      uname(&systemInfo)
      let machineMirror = Mirror(reflecting: systemInfo.machine)
      return machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
      }
    #elseif os(macOS)
      return "Mac"
    #else
      return "Unknown"
    #endif
  }

  /// Device name for display purposes (e.g. API key comments). A readable base
  /// plus a short per-install suffix, since neither base alone can tell
  /// KMReader installs apart: since iOS 16, `UIDevice.current.name` returns
  /// only a generic model name ("iPhone") without the restricted
  /// user-assigned-device-name entitlement, and macOS host names are
  /// user-assigned and not unique across machines.
  @MainActor
  static var deviceName: String {
    #if os(iOS) || os(tvOS)
      return "\(machineIdentifier) · \(deviceNameSuffix)"
    #elseif os(macOS)
      return "\(Host.current().localizedName ?? "Mac") · \(deviceNameSuffix)"
    #else
      return "Unknown"
    #endif
  }

  /// Short, stable suffix derived from the per-install device identifier.
  @MainActor
  private static var deviceNameSuffix: String {
    let id = AppConfig.deviceIdentifier
    guard !id.isEmpty else { return "KMReader" }
    return String(id.prefix(6)).uppercased()
  }

  @MainActor
  static var defaultDashboardCardWidth: CGFloat {
    #if os(tvOS)
      return 240
    #elseif os(macOS)
      return 160
    #elseif os(iOS)
      return isPad ? 160 : 120
    #else
      return 120
    #endif
  }

  @MainActor
  static var sheetPadding: CGFloat {
    #if os(tvOS)
      return 24
    #elseif os(macOS)
      return 16
    #else
      return 8
    #endif
  }

  @MainActor
  static var buttonSpacing: CGFloat {
    #if os(tvOS)
      return 36
    #elseif os(macOS)
      return 24
    #else
      return 12
    #endif
  }

  @MainActor
  static var iconSize: CGFloat {
    #if os(tvOS)
      return 24
    #elseif os(macOS)
      return 14
    #else
      return 12
    #endif
  }

  @MainActor
  static var detailThumbnailWidth: CGFloat {
    #if os(tvOS)
      return 240
    #elseif os(macOS)
      return 180
    #else
      return 120
    #endif
  }

  @MainActor
  static var progressBarHeight: CGFloat {
    #if os(tvOS)
      return 6
    #elseif os(macOS)
      return 4
    #elseif os(iOS)
      return isPad ? 4 : 4
    #else
      return 4
    #endif
  }

  @MainActor
  static var bottomEdgeHorizontalPadding: CGFloat {
    #if os(iOS)
      if isPad {
        return 24
      }

      let width = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)

      if width >= 420 {
        return 64
      }

      if width <= 375 {
        return 36
      }

      return 48
    #elseif os(macOS)
      return 24
    #else
      return 24
    #endif
  }

  @MainActor
  static var pageNumberFontSize: CGFloat {
    #if os(tvOS)
      return 24
    #elseif os(macOS)
      return 16
    #elseif os(iOS)
      return 14
    #else
      return 14
    #endif
  }

  /// Get device orientation
  /// - iOS: use `UIDevice.current.orientation`
  /// - tvOS / macOS: always return `.landscape`
  /// - Others: `.unknown`
  @MainActor
  static var deviceOrientation: DeviceOrientation {
    #if os(tvOS) || os(macOS)
      return .landscape
    #elseif os(iOS)
      let orientation = UIDevice.current.orientation
      if orientation.isLandscape {
        return .landscape
      } else if orientation.isPortrait {
        return .portrait
      } else {
        return .unknown
      }
    #else
      return .unknown
    #endif
  }

  #if os(iOS) || os(macOS)
    /// Get pasteboard for copying text (iOS and macOS only)
    static nonisolated var generalPasteboard: PlatformPasteboard {
      #if os(iOS)
        return UIPasteboard.general
      #elseif os(macOS)
        return NSPasteboard.general
      #endif
    }
  #endif

  /// Get the maximum dimension of the screen to validate geometry values
  @MainActor
  static var maxScreenDimension: CGFloat {
    #if os(iOS) || os(tvOS)
      let bounds = UIScreen.main.bounds
      return max(bounds.width, bounds.height)
    #elseif os(macOS)
      if let screen = NSScreen.main {
        return max(screen.frame.width, screen.frame.height)
      }
      return 3000
    #else
      return 3000
    #endif
  }

  /// Check if a width value is valid (not anomalously large during app transitions)
  @MainActor
  static func isValidWidth(_ width: CGFloat) -> Bool {
    return width <= maxScreenDimension * 1.2
  }

  /// Get system background color
  /// - Returns: System background color appropriate for the platform
  static nonisolated var systemBackgroundColor: Color {
    #if os(iOS)
      return Color(.systemBackground)
    #elseif os(macOS)
      return Color(NSColor.controlBackgroundColor)
    #else
      return .gray
    #endif
  }

  /// Get secondary system background color
  /// - Returns: Secondary system background color appropriate for the platform
  static nonisolated var secondarySystemBackgroundColor: Color {
    #if os(iOS)
      return Color(.secondarySystemBackground)
    #elseif os(macOS)
      return Color(NSColor.controlBackgroundColor).opacity(0.5)
    #else
      return .gray.opacity(0.5)
    #endif
  }

  /// Convert PlatformImage to PNG data
  /// - Parameter image: Platform image to convert
  /// - Returns: PNG data if conversion succeeds, nil otherwise
  static nonisolated func pngData(from image: PlatformImage) -> Data? {
    #if os(iOS)
      return image.pngData()
    #elseif os(macOS)
      guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
      }
      let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
      return bitmapRep.representation(using: .png, properties: [:])
    #else
      return nil
    #endif
  }
}

enum DeviceOrientation {
  case portrait
  case landscape
  case unknown

  var isLandscape: Bool {
    self == .landscape
  }

  var isPortrait: Bool {
    self == .portrait
  }
}

#if os(macOS)
  extension NSPasteboard {
    var string: String? {
      get {
        return self.string(forType: .string)
      }
      set {
        if let value = newValue {
          self.clearContents()
          self.setString(value, forType: .string)
        }
      }
    }
  }
#endif

extension Image {
  /// Create a SwiftUI Image from a PlatformImage (UIImage on iOS/tvOS, NSImage on macOS)
  init(platformImage: PlatformImage) {
    #if os(iOS) || os(tvOS)
      self.init(uiImage: platformImage)
    #elseif os(macOS)
      self.init(nsImage: platformImage)
    #endif
  }
}
