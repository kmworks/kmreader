//
// ThumbnailImage.swift
//
//

import SwiftUI

/// A reusable thumbnail image component using native image loading
struct ThumbnailImage<Overlay: View, Menu: View>: View {
  let id: String
  let type: ThumbnailType
  let shadowStyle: ShadowStyle
  let contentBlurRadius: CGFloat
  let width: CGFloat?
  let cornerRadius: CGFloat
  let alignment: Alignment
  let isTransitionSource: Bool
  let navigationLink: NavDestination?
  let preserveAspectRatioOverride: Bool?
  let onAction: (() -> Void)?
  let overlay: (() -> Overlay)?
  let menu: (() -> Menu)?

  @AppStorage("thumbnailPreserveAspectRatio") private var thumbnailPreserveAspectRatio: Bool = true
  @AppStorage("thumbnailShowShadow") private var thumbnailShowShadow: Bool = true
  @Environment(\.zoomNamespace) private var zoomNamespace

  @State private var isLoading: Bool = true
  @State private var image: PlatformImage?
  @State private var currentBaseKey: String?
  @State private var loadedImageSize: CGSize?
  @State private var refreshTrigger: UUID = UUID()

  private var effectiveShadowStyle: ShadowStyle {
    return thumbnailShowShadow ? shadowStyle : .none
  }

  private var effectivePreserveAspectRatio: Bool {
    preserveAspectRatioOverride ?? thumbnailPreserveAspectRatio
  }

  @ViewBuilder
  private func interactiveThumbnailBase<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .matchedTransitionSourceIfAvailable(id: id, in: isTransitionSource ? zoomNamespace : nil)
      #if os(iOS)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius))
      #endif
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
      .withNavigationLink(navigationLink, cornerRadius: cornerRadius)
      .withButtonAction(onAction, cornerRadius: cornerRadius)
      .withContextMenu(Menu.self == EmptyView.self ? nil : menu)
  }

  // Defines the card edge where covers blend into the background — dark
  // covers, or any cover in dark mode where the shadow is too faint to see.
  private var borderOverlay: some View {
    RoundedRectangle(cornerRadius: cornerRadius)
      .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
  }

  init(
    id: String,
    type: ThumbnailType = .book,
    shadowStyle: ShadowStyle = .basic,
    contentBlurRadius: CGFloat = 0,
    width: CGFloat? = nil,
    cornerRadius: CGFloat = 8,
    alignment: Alignment = .center,
    isTransitionSource: Bool = true,
    navigationLink: NavDestination? = nil,
    preserveAspectRatioOverride: Bool? = nil,
    onAction: (() -> Void)? = nil,
    @ViewBuilder overlay: @escaping () -> Overlay,
    @ViewBuilder menu: @escaping () -> Menu,
  ) {
    self.id = id
    self.type = type
    self.shadowStyle = shadowStyle
    self.contentBlurRadius = max(0, contentBlurRadius)
    self.width = width
    self.cornerRadius = cornerRadius
    self.alignment = alignment
    self.isTransitionSource = isTransitionSource
    self.navigationLink = navigationLink
    self.preserveAspectRatioOverride = preserveAspectRatioOverride
    self.onAction = onAction
    self.overlay = overlay
    self.menu = menu

    let cached = ThumbnailCache.cachedImage(id: id, type: type)
    _isLoading = State(initialValue: cached == nil)
    _image = State(initialValue: cached)
    _currentBaseKey = State(initialValue: cached != nil ? "\(id)#\(type.rawValue)" : nil)
    _loadedImageSize = State(initialValue: cached?.size)
  }

  private var baseKey: String {
    "\(id)#\(type.rawValue)"
  }

  private var loadTaskKey: String {
    "\(baseKey)#\(refreshTrigger.uuidString)"
  }

  private var imageAspectRatio: CGFloat {
    guard let loadedImageSize = loadedImageSize, loadedImageSize.height > 0 else {
      return CoverAspectRatio.widthToHeight
    }
    return loadedImageSize.width / loadedImageSize.height
  }

  private var isAbnormalSize: Bool {
    guard let loadedImageSize = loadedImageSize else { return false }
    guard effectivePreserveAspectRatio else { return false }
    let realRatio = loadedImageSize.height / loadedImageSize.width
    return realRatio < 0.35 || realRatio > 4.242
  }

  var body: some View {
    thumbnailSurface
      .onReceive(NotificationCenter.default.publisher(for: .thumbnailDidRefresh)) { notification in
        guard let userInfo = notification.userInfo,
          let notificationId = userInfo["id"] as? String,
          let notificationType = userInfo["type"] as? String,
          notificationId == id,
          notificationType == type.rawValue
        else {
          return
        }
        currentBaseKey = nil
        refreshTrigger = UUID()
      }
      .task(id: loadTaskKey) {
        if currentBaseKey != baseKey {
          currentBaseKey = baseKey
          image = nil
          loadedImageSize = nil
        }
        guard image == nil else { return }

        isLoading = true
        let loaded = await ThumbnailCache.shared.image(id: id, type: type)
        guard !Task.isCancelled, currentBaseKey == baseKey else { return }
        if let loaded = loaded {
          loadedImageSize = loaded.size
          image = loaded
        }
        isLoading = false
      }
  }

  private var thumbnailSurface: some View {
    thumbnailSlot
      .overlay {
        GeometryReader { proxy in
          thumbnailContent(in: proxy.size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
      }
      .animation(.appCurve(0.18), value: image != nil)
      .animation(.appCurve(0.18), value: contentBlurRadius)
      .overlay {
        if isAbnormalSize, let overlay = overlay {
          overlay()
        }
      }
  }

  private var thumbnailSlot: some View {
    Color.clear
      .aspectRatio(CoverAspectRatio.widthToHeight, contentMode: .fit)
      .frame(width: width)
  }

  @ViewBuilder
  private func thumbnailContent(in slotSize: CGSize) -> some View {
    let displaySize = displayedContentSize(in: slotSize)

    if image != nil {
      interactiveThumbnailBase {
        imageCard
          .frame(width: displaySize.width, height: displaySize.height)
      }
      .transition(.opacity.combined(with: .scale(scale: 0.98)))
    } else {
      interactiveThumbnailBase {
        placeholderCard(shimmering: isLoading)
          .frame(width: displaySize.width, height: displaySize.height)
      }
      .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
  }

  private func displayedContentSize(in slotSize: CGSize) -> CGSize {
    guard slotSize.width.isFinite, slotSize.height.isFinite, slotSize.width > 0, slotSize.height > 0
    else {
      return .zero
    }
    guard image != nil, effectivePreserveAspectRatio else {
      return slotSize
    }

    let aspectRatio = max(imageAspectRatio, CGFloat.leastNonzeroMagnitude)
    let slotAspectRatio = slotSize.width / slotSize.height
    if aspectRatio > slotAspectRatio {
      return CGSize(width: slotSize.width, height: slotSize.width / aspectRatio)
    }
    return CGSize(width: slotSize.height * aspectRatio, height: slotSize.height)
  }

  @ViewBuilder
  var imageContent: some View {
    if let platformImage = image {
      if effectivePreserveAspectRatio {
        if contentBlurRadius > 0 {
          Image(platformImage: platformImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .blur(radius: contentBlurRadius)
        } else {
          Image(platformImage: platformImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
        }
      } else {
        GeometryReader { proxy in
          if contentBlurRadius > 0 {
            Image(platformImage: platformImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: proxy.size.width, height: proxy.size.height)
              .blur(radius: contentBlurRadius)
              .clipped()
          } else {
            Image(platformImage: platformImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: proxy.size.width, height: proxy.size.height)
              .clipped()
          }
        }
      }
    }
  }

  @ViewBuilder
  private var imageCard: some View {
    if effectivePreserveAspectRatio {
      framedImageCard
        .aspectRatio(imageAspectRatio, contentMode: .fit)
        .shadowStyle(effectiveShadowStyle, cornerRadius: cornerRadius)
    } else {
      framedImageCard
        .shadowStyle(effectiveShadowStyle, cornerRadius: cornerRadius)
    }
  }

  private var framedImageCard: some View {
    imageContent
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .overlay {
        if !isAbnormalSize, let overlay = overlay {
          overlay()
        }
      }
      // Above the content overlay so the text-overlay gradient cannot dim it.
      .overlay { borderOverlay }
  }

  /// A failed load stays static: shimmer reads as a load still in flight.
  @ViewBuilder
  private func placeholderCard(shimmering: Bool) -> some View {
    if shimmering {
      placeholderBase
        .shimmer(cornerRadius: cornerRadius)
        .overlay { placeholderOverlay }
        .overlay { borderOverlay }
    } else {
      placeholderBase
        .overlay { placeholderOverlay }
        .overlay { borderOverlay }
    }
  }

  /// The overlay slot also renders before the cover loads, so an unloaded
  /// card still shows its text overlay and badge.
  @ViewBuilder
  private var placeholderOverlay: some View {
    if let overlay = overlay {
      overlay()
    }
  }

  private var placeholderBase: some View {
    RoundedRectangle(cornerRadius: cornerRadius)
      .fill(Color.gray.opacity(0.2))
  }
}

extension ThumbnailImage where Overlay == EmptyView, Menu == EmptyView {
  init(
    id: String,
    type: ThumbnailType = .book,
    shadowStyle: ShadowStyle = .basic,
    contentBlurRadius: CGFloat = 0,
    width: CGFloat? = nil,
    cornerRadius: CGFloat = 8,
    alignment: Alignment = .center,
    isTransitionSource: Bool = true,
    navigationLink: NavDestination? = nil,
    preserveAspectRatioOverride: Bool? = nil,
    onAction: (() -> Void)? = nil,
  ) {
    self.init(
      id: id, type: type, shadowStyle: shadowStyle, contentBlurRadius: contentBlurRadius,
      width: width, cornerRadius: cornerRadius,
      alignment: alignment,
      isTransitionSource: isTransitionSource,
      navigationLink: navigationLink,
      preserveAspectRatioOverride: preserveAspectRatioOverride,
      onAction: onAction
    ) {
    } menu: {
    }
  }
}

extension ThumbnailImage where Menu == EmptyView {
  init(
    id: String,
    type: ThumbnailType = .book,
    shadowStyle: ShadowStyle = .basic,
    contentBlurRadius: CGFloat = 0,
    width: CGFloat? = nil,
    cornerRadius: CGFloat = 8,
    alignment: Alignment = .center,
    isTransitionSource: Bool = true,
    navigationLink: NavDestination? = nil,
    preserveAspectRatioOverride: Bool? = nil,
    onAction: (() -> Void)? = nil,
    @ViewBuilder overlay: @escaping () -> Overlay
  ) {
    self.init(
      id: id, type: type, shadowStyle: shadowStyle, contentBlurRadius: contentBlurRadius,
      width: width, cornerRadius: cornerRadius,
      alignment: alignment,
      isTransitionSource: isTransitionSource,
      navigationLink: navigationLink,
      preserveAspectRatioOverride: preserveAspectRatioOverride,
      onAction: onAction
    ) {
      overlay()
    } menu: {
    }
  }
}

extension View {
  @ViewBuilder
  func withContextMenu<MenuItems: View>(_ menu: (() -> MenuItems)?) -> some View {
    // An empty contextMenu modifier still captures long-presses and blocks any
    // ancestor's context menu, so only attach it when there is a real menu.
    if let menu {
      contextMenu {
        menu()
      }
    } else {
      self
    }
  }
  @ViewBuilder
  func withButtonAction(_ onAction: (() -> Void)?, cornerRadius: CGFloat = 8) -> some View {
    if let onAction = onAction {
      Button(action: onAction) {
        self
      }
      .adaptiveButtonStyle(.plain)
    } else {
      self
    }
  }

  @ViewBuilder
  func withNavigationLink(_ navigationLink: NavDestination?, cornerRadius: CGFloat = 8) -> some View {
    if let navigationLink = navigationLink {
      NavigationLink(value: navigationLink) {
        self
      }
      .adaptiveButtonStyle(.plain)
    } else {
      self
    }
  }
}

#Preview {
  VStack {
    ThumbnailImage(
      id: "1",
      type: .book,
      shadowStyle: .platform,
      cornerRadius: 8,
      alignment: .bottom
    )
    .frame(width: 200)
  }
}
