//
// ReaderSettingsSheet.swift
//
//

import SwiftUI

struct ReaderSettingsSheet: View {
  let readingDirection: ReadingDirection

  // Persisted settings (via @AppStorage)
  @AppStorage("readerBackground") private var readerBackground: ReaderBackground = .system
  @AppStorage("webtoonPageWidthPercentage") private var webtoonPageWidthPercentage: Double = 100.0
  @AppStorage("webtoonTapScrollPercentage") private var webtoonTapScrollPercentage: Double = 80.0
  @AppStorage("showPageNumber") private var showPageNumber: Bool = true
  @AppStorage("showPageShadow") private var showPageShadow: Bool = AppConfig.showPageShadow
  @AppStorage("doubleTapZoomScale") private var doubleTapZoomScale: Double = 3.0
  @AppStorage("doubleTapZoomMode") private var doubleTapZoomMode: DoubleTapZoomMode = .enabled
  @AppStorage("pageTransitionStyle") private var pageTransitionStyle: PageTransitionStyle = .cover
  @AppStorage("tapZoneMode") private var tapZoneMode: TapZoneMode = .defaultLayout
  @AppStorage("tapZoneInversionMode") private var tapZoneInversionMode: TapZoneInversionMode = .auto
  @AppStorage("showTapZoneHints") private var showTapZoneHints: Bool = true
  @AppStorage("animateTapTurns") private var animateTapTurns: Bool = AppConfig.animateTapTurns
  @AppStorage("showKeyboardHelpOverlay") private var showKeyboardHelpOverlay: Bool = true
  @AppStorage("enableLiveText") private var enableLiveText: Bool = false
  @AppStorage("imageUpscalingMode") private var imageUpscalingMode: ReaderImageUpscalingMode =
    AppConfig.imageUpscalingMode
  @AppStorage("imageUpscaleAutoTriggerScale") private var imageUpscaleAutoTriggerScale: Double =
    AppConfig.imageUpscaleAutoTriggerScale
  @AppStorage("imageUpscaleAlwaysMaxScreenScale")
  private var imageUpscaleAlwaysMaxScreenScale: Double =
    AppConfig.imageUpscaleAlwaysMaxScreenScale
  @AppStorage("divinaPageBorderCropMode") private var divinaPageBorderCropMode: ReaderPageBorderCropMode =
    AppConfig.divinaPageBorderCropMode
  @AppStorage("shakeToOpenLiveText") private var shakeToOpenLiveText: Bool = false
  @AppStorage("enableDivinaImageContextMenu")
  private var enableDivinaImageContextMenu: Bool = AppConfig.enableDivinaImageContextMenu
  @AppStorage("showDivinaControlsGradientBackground")
  private var showControlsGradientBackground: Bool =
    AppConfig.showDivinaControlsGradientBackground
  @AppStorage("showDivinaProgressBarWhileReading")
  private var showProgressBarWhileReading: Bool =
    AppConfig.showDivinaProgressBarWhileReading
  @AppStorage("divinaPreloadProfile") private var divinaPreloadProfile: ReaderPreloadProfile = .balanced

  private var isWebtoonDirection: Bool {
    readingDirection == .webtoon
  }

  private var shouldShowPagedTurnSettings: Bool {
    !isWebtoonDirection
  }

  private var shouldShowTapTurnAnimation: Bool {
    isWebtoonDirection || shouldShowPagedTurnSettings
  }

  private var doubleTapZoomEnabled: Binding<Bool> {
    Binding(
      get: { doubleTapZoomMode.isEnabled },
      set: { doubleTapZoomMode = $0 ? .enabled : .disabled }
    )
  }

  var body: some View {
    SheetView(
      title: String(localized: "Reader Settings"), size: .large, applyFormStyle: true
    ) {
      Form {
        // MARK: - Appearance Section

        Section(header: Text("Appearance")) {
          Picker("Reader Background", selection: $readerBackground) {
            ForEach(ReaderBackground.allCases, id: \.self) { background in
              Text(background.displayName).tag(background)
            }
          }
          .pickerStyle(.menu)

          Toggle(isOn: $showPageNumber) {
            Text("Show Page Number")
          }

          Toggle(isOn: $showPageShadow) {
            Text("Show Page Shadow")
          }

          Toggle(isOn: $showControlsGradientBackground) {
            Text("Controls Gradient Background")
          }

          Toggle(isOn: $showProgressBarWhileReading) {
            Text("Show Progress Bar While Reading")
          }

          #if os(iOS) || os(macOS)
            if isWebtoonDirection {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Text("Webtoon Page Width")
                  Spacer()
                  Text(webtoonPageWidthPercentage / 100, format: .percent.precision(.fractionLength(0)))
                    .foregroundColor(.secondary)
                }
                Slider(
                  value: $webtoonPageWidthPercentage,
                  in: 50...100,
                  step: 5
                )
              }
            }
          #endif

        }

        // MARK: - Page Turn Section

        Section(header: Text("Page Turn")) {
          if shouldShowPagedTurnSettings {
            Picker("Page Transition Style", selection: $pageTransitionStyle) {
              ForEach(PageTransitionStyle.availableCases, id: \.self) { style in
                Text(style.displayName).tag(style)
              }
            }
            .pickerStyle(.menu)
          }

          #if os(iOS) || os(macOS)
            if shouldShowTapTurnAnimation {
              Toggle(isOn: $animateTapTurns) {
                Text("Animate Page Turns")
              }
            }
          #endif

          Toggle(isOn: $showKeyboardHelpOverlay) {
            Text("Auto-Show Keyboard Help")
          }

          #if os(iOS) || os(macOS)
            TapZoneModePicker(
              selection: $tapZoneMode,
              tapZoneInversionMode: tapZoneInversionMode,
              readingDirection: readingDirection
            )

            if !tapZoneMode.isDisabled {
              Picker("Tap Zone Mirroring", selection: $tapZoneInversionMode) {
                ForEach(TapZoneInversionMode.allCases, id: \.self) { mode in
                  Text(mode.displayName).tag(mode)
                }
              }
              .pickerStyle(.menu)

              Toggle(isOn: $showTapZoneHints) {
                Text("Show Tap Zone Hints")
              }

              if isWebtoonDirection {
                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    Text("Webtoon Tap Scroll Height")
                    Spacer()
                    Text(webtoonTapScrollPercentage / 100, format: .percent.precision(.fractionLength(0)))
                      .foregroundColor(.secondary)
                  }
                  Slider(
                    value: $webtoonTapScrollPercentage,
                    in: 25...100,
                    step: 5
                  )
                }
              }
            }
          #endif
        }

        Section(header: Text("Performance")) {
          Picker("Image Preloading", selection: $divinaPreloadProfile) {
            ForEach(ReaderPreloadProfile.allCases) { profile in
              Text(profile.displayName).tag(profile)
            }
          }
          .pickerStyle(.menu)
        }

        #if os(iOS)
          Section(header: Text("Zooming")) {
            Toggle(isOn: doubleTapZoomEnabled) {
              Text("Double Tap to Zoom")
            }
            if doubleTapZoomMode.isEnabled {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Text("Double Tap Zoom Scale")
                  Spacer()
                  Text(String(format: "%.1fx", doubleTapZoomScale))
                    .foregroundColor(.secondary)
                }
                Slider(
                  value: $doubleTapZoomScale,
                  in: 1.0...8.0,
                  step: 0.5
                )
              }
            }
          }
        #endif

        #if os(iOS) || os(macOS)
          Section(header: Text("Image Processing")) {
            Picker("Border Cropping", selection: $divinaPageBorderCropMode) {
              ForEach(ReaderPageBorderCropMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
              }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 8) {
              Picker("Waifu2x Mode", selection: $imageUpscalingMode) {
                ForEach(ReaderImageUpscalingMode.allCases, id: \.self) { mode in
                  Text(mode.displayName).tag(mode)
                }
              }
              .pickerStyle(.menu)
            }

            Group {
              switch imageUpscalingMode {
              case .auto:
                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    Text("Auto Trigger Scale Threshold")
                    Spacer()
                    Text(String(format: "%.2fx", imageUpscaleAutoTriggerScale))
                      .foregroundColor(.secondary)
                  }
                  Slider(
                    value: $imageUpscaleAutoTriggerScale,
                    in: 1.0...1.5,
                    step: 0.01
                  )
                }
              case .always:
                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    Text("Always Mode Source Size Threshold")
                    Spacer()
                    Text(String(format: "%.2fx", imageUpscaleAlwaysMaxScreenScale))
                      .foregroundColor(.secondary)
                  }
                  Slider(
                    value: $imageUpscaleAlwaysMaxScreenScale,
                    in: 1.0...3.0,
                    step: 0.05
                  )
                }
              case .disabled:
                EmptyView()
              }
            }
          }
        #endif

        #if os(iOS) || os(macOS)
          Section(header: Text("Live Text")) {
            Toggle(isOn: $enableLiveText) {
              Text("Enable Live Text")
            }
            #if os(iOS)
              Toggle(isOn: $shakeToOpenLiveText) {
                Text("Shake to Open Live Text")
              }
            #endif
          }
        #endif

        #if os(iOS) || os(macOS)
          Section(header: Text("Context Menu")) {
            Toggle(isOn: $enableDivinaImageContextMenu) {
              Text("Enable Image Context Menu")
            }
          }
        #endif
      }
    }
    .animation(.default, value: tapZoneMode)
    .animation(.default, value: doubleTapZoomMode)
    .animation(.default, value: imageUpscalingMode)
    .animation(.default, value: divinaPageBorderCropMode)
    .animation(.default, value: pageTransitionStyle)
    .animation(.default, value: readingDirection)
    .presentationDragIndicator(.visible)
  }
}
