//
// SettingsCacheView.swift
//
//

import SwiftUI

struct SettingsCacheView: View {
  @AppStorage("maxPageCacheSize") private var maxPageCacheSize: Int = 8
  @AppStorage("maxCoverCacheSize") private var maxCoverCacheSize: Int = 512
  @AppStorage("coverCacheExpirationDays") private var coverCacheExpirationDays: Int = 7
  @State private var showClearImageCacheConfirmation = false
  @State private var showClearAllImageCacheConfirmation = false
  @State private var showClearCoverCacheConfirmation = false
  @State private var showClearAllCoverCacheConfirmation = false
  @State private var imageCacheSize: Int64 = 0
  @State private var imageCacheCount: Int = 0
  @State private var thumbnailCacheSize: Int64 = 0
  @State private var thumbnailCacheCount: Int = 0
  @State private var isLoadingCacheSize = false

  #if os(iOS) || os(macOS)
    @State private var isEditingPageCacheSlider = false
    @State private var isEditingCoverCacheSlider = false

    private var maxCacheSizeBinding: Binding<Double> {
      Binding(
        get: { Double(maxPageCacheSize) },
        set: { maxPageCacheSize = Int($0) }
      )
    }

    private var maxCoverCacheSizeBinding: Binding<Double> {
      Binding(
        get: { Double(maxCoverCacheSize) },
        set: { maxCoverCacheSize = Int($0) }
      )
    }

    private var coverCacheExpirationDaysBinding: Binding<Double> {
      Binding(
        get: { Double(max(1, coverCacheExpirationDays)) },
        set: { coverCacheExpirationDays = max(1, Int($0)) }
      )
    }
  #else
    @State private var cacheSizeText: String = ""
    @State private var coverCacheSizeText: String = ""
    @State private var coverCacheExpirationDaysText: String = ""

    private var cacheSizeTextFieldBinding: Binding<String> {
      Binding(
        get: { cacheSizeText.isEmpty ? "\(maxPageCacheSize)" : cacheSizeText },
        set: { newValue in
          cacheSizeText = newValue
          if let value = Int(newValue), value >= 1, value <= 20 {
            maxPageCacheSize = value
          }
        }
      )
    }

    private var coverCacheSizeTextFieldBinding: Binding<String> {
      Binding(
        get: {
          coverCacheSizeText.isEmpty ? "\(maxCoverCacheSize)" : coverCacheSizeText
        },
        set: { newValue in
          coverCacheSizeText = newValue
          if let value = Int(newValue), value >= 128, value <= 8192 {
            maxCoverCacheSize = value
          }
        }
      )
    }

    private var coverCacheExpirationDaysTextFieldBinding: Binding<String> {
      Binding(
        get: {
          coverCacheExpirationDaysText.isEmpty
            ? "\(coverCacheExpirationDays)" : coverCacheExpirationDaysText
        },
        set: { newValue in
          coverCacheExpirationDaysText = newValue
          if let value = Int(newValue), value >= 1, value <= 90 {
            coverCacheExpirationDays = value
          }
        }
      )
    }
  #endif

  var body: some View {
    Form {
      Section(header: Text("Page")) {
        VStack(alignment: .leading, spacing: 8) {
          #if os(iOS) || os(macOS)
            HStack {
              Text("Maximum Size")
              Spacer()
              Text("\(maxPageCacheSize) GB")
                .foregroundColor(.secondary)
            }
            Slider(
              value: maxCacheSizeBinding,
              in: 1...20,
              step: 1
            ) { editing in
              isEditingPageCacheSlider = editing
            }
          #else
            HStack {
              Text("Maximum Size (GB)")
              Spacer()
              TextField("GB", text: cacheSizeTextFieldBinding)
                .frame(maxWidth: 240)
                .multilineTextAlignment(.trailing)
                .onAppear {
                  cacheSizeText = "\(maxPageCacheSize)"
                }
                .onChange(of: maxPageCacheSize) { _, newValue in
                  if cacheSizeText != "\(newValue)" {
                    cacheSizeText = "\(newValue)"
                  }
                }
            }
          #endif
          Text(
            "Adjust the maximum size of the page cache. Cache will be cleaned automatically when exceeded."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }

        HStack {
          Text("Cached Size")
          Spacer()
          if isLoadingCacheSize {
            LoadingIcon()
          } else {
            Text(formatCacheSize(imageCacheSize))
              .foregroundColor(.secondary)
          }
        }
        .tvFocusableHighlight()

        HStack {
          Text("Cached Images")
          Spacer()
          if isLoadingCacheSize {
            LoadingIcon()
          } else {
            Text(formatCacheCount(imageCacheCount))
              .foregroundColor(.secondary)
          }
        }
        .tvFocusableHighlight()

        HStack {
          Button(role: .destructive) {
            showClearAllImageCacheConfirmation = true
          } label: {
            Text("Clear All")
              .frame(maxWidth: .infinity)
          }
          Button(role: .destructive) {
            showClearImageCacheConfirmation = true
          } label: {
            Text("Clear Current")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
      }

      Section(header: Text(String(localized: "Cover"))) {
        VStack(alignment: .leading, spacing: 8) {
          #if os(iOS) || os(macOS)
            HStack {
              Text("Maximum Size")
              Spacer()
              Text("\(maxCoverCacheSize) MB")
                .foregroundColor(.secondary)
            }
            Slider(
              value: maxCoverCacheSizeBinding,
              in: 128...8192,
              step: 128
            ) { editing in
              isEditingCoverCacheSlider = editing
            }
          #else
            HStack {
              Text("Maximum Size (MB)")
              Spacer()
              TextField("MB", text: coverCacheSizeTextFieldBinding)
                .frame(maxWidth: 240)
                .multilineTextAlignment(.trailing)
                .onAppear {
                  coverCacheSizeText = "\(maxCoverCacheSize)"
                }
                .onChange(of: maxCoverCacheSize) { _, newValue in
                  if coverCacheSizeText != "\(newValue)" {
                    coverCacheSizeText = "\(newValue)"
                  }
                }
            }
          #endif
          Text(
            "Adjust the maximum size of the cover cache. Cache will be cleaned automatically when exceeded."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
          #if os(iOS) || os(macOS)
            HStack {
              Text("Expiration")
              Spacer()
              Text("\(max(1, coverCacheExpirationDays)) days")
                .foregroundColor(.secondary)
            }
            Slider(
              value: coverCacheExpirationDaysBinding,
              in: 1...90,
              step: 1
            )
          #else
            HStack {
              Text("Expiration (days)")
              Spacer()
              TextField("Days", text: coverCacheExpirationDaysTextFieldBinding)
                .frame(maxWidth: 240)
                .multilineTextAlignment(.trailing)
                .onAppear {
                  coverCacheExpirationDaysText = "\(coverCacheExpirationDays)"
                }
                .onChange(of: coverCacheExpirationDays) { _, newValue in
                  if coverCacheExpirationDaysText != "\(newValue)" {
                    coverCacheExpirationDaysText = "\(newValue)"
                  }
                }
            }
          #endif
          Text("Refresh cached covers after this many days.")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        HStack {
          Text("Cached Size")
          Spacer()
          if isLoadingCacheSize {
            LoadingIcon()
          } else {
            Text(formatCacheSize(thumbnailCacheSize))
              .foregroundColor(.secondary)
          }
        }
        .tvFocusableHighlight()

        HStack {
          Text(String(localized: "Cached Covers"))
          Spacer()
          if isLoadingCacheSize {
            LoadingIcon()
          } else {
            Text(formatCacheCount(thumbnailCacheCount))
              .foregroundColor(.secondary)
          }
        }
        .tvFocusableHighlight()

        HStack {
          Button(role: .destructive) {
            showClearAllCoverCacheConfirmation = true
          } label: {
            Text("Clear All")
              .frame(maxWidth: .infinity)
          }
          Button(role: .destructive) {
            showClearCoverCacheConfirmation = true
          } label: {
            Text("Clear Current")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
      }

    }
    .formStyle(.grouped)
    .platformNavigationTitle(SettingsSection.cache.title)
    .alert("Clear Page (Current Server)", isPresented: $showClearImageCacheConfirmation) {
      Button("Clear", role: .destructive) {
        Task {
          await ImageCache.clearCurrentInstanceDiskCache()
          ErrorManager.shared.notify(
            message: String(localized: "notification.cache.pageClearedCurrent")
          )
          await loadCacheSize()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This will remove cached page images for the current server. Images will be re-downloaded when needed."
      )
    }
    .alert("Clear Page (All Servers)", isPresented: $showClearAllImageCacheConfirmation) {
      Button("Clear", role: .destructive) {
        Task {
          await ImageCache.clearAllDiskCache()
          ErrorManager.shared.notify(
            message: String(localized: "notification.cache.pageClearedAll")
          )
          await loadCacheSize()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This will remove all cached page images for all servers. Images will be re-downloaded when needed."
      )
    }
    .alert(
      String(localized: "Clear Cover (Current Server)"),
      isPresented: $showClearCoverCacheConfirmation
    ) {
      Button("Clear", role: .destructive) {
        Task {
          await ThumbnailCache.clearCurrentInstanceDiskCache()
          ErrorManager.shared.notify(
            message: String(localized: "notification.cache.coverClearedCurrent")
          )
          await loadCacheSize()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This will remove cached covers for the current server. Covers will be re-downloaded when needed."
      )
    }
    .alert(
      String(localized: "Clear Cover (All Servers)"),
      isPresented: $showClearAllCoverCacheConfirmation
    ) {
      Button("Clear", role: .destructive) {
        Task {
          await ThumbnailCache.clearAllDiskCache()
          ErrorManager.shared.notify(
            message: String(localized: "notification.cache.coverClearedAll")
          )
          await loadCacheSize()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This will remove all cached covers for all servers. Covers will be re-downloaded when needed."
      )
    }
    .task {
      await loadCacheSize()
    }
    .onChange(of: maxPageCacheSize) {
      // Only trigger cache cleanup after slider dragging ends
      #if os(iOS) || os(macOS)
        guard !isEditingPageCacheSlider else { return }
      #endif
      Task {
        await ImageCache.cleanupDiskCacheIfNeeded()
        await loadCacheSize()
      }
    }
    .onChange(of: maxCoverCacheSize) {
      // Only trigger cache cleanup after slider dragging ends
      #if os(iOS) || os(macOS)
        guard !isEditingCoverCacheSlider else { return }
      #endif
      Task {
        await ThumbnailCache.cleanupDiskCacheIfNeeded()
        await loadCacheSize()
      }
    }
  }

  private func loadCacheSize() async {
    isLoadingCacheSize = true
    async let imageSize = ImageCache.getDiskCacheSize()
    async let imageCount = ImageCache.getDiskCacheCount()
    async let thumbnailSize = ThumbnailCache.getDiskCacheSize()
    async let thumbnailCount = ThumbnailCache.getDiskCacheCount()

    imageCacheSize = await imageSize
    imageCacheCount = await imageCount
    thumbnailCacheSize = await thumbnailSize
    thumbnailCacheCount = await thumbnailCount
    isLoadingCacheSize = false
  }

  private func formatCacheSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  private func formatCacheCount(_ count: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
  }

}
