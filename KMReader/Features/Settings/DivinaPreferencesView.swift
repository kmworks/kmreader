//
// DivinaPreferencesView.swift
//
//

import SwiftUI

struct DivinaPreferencesView: View {
  @AppStorage("showTapZoneHints") private var showTapZoneHints: Bool = true
  @AppStorage("tapZoneMode") private var tapZoneMode: TapZoneMode = .defaultLayout
  @AppStorage("tapZoneInversionMode") private var tapZoneInversionMode: TapZoneInversionMode = .auto
  @AppStorage("showKeyboardHelpOverlay") private var showKeyboardHelpOverlay: Bool = true
  @AppStorage("readerBackground") private var readerBackground: ReaderBackground = .system
  @AppStorage("pageLayout") private var pageLayout: PageLayout = .auto
  @AppStorage("isolateCoverPage") private var isolateCoverPage: Bool = true
  @AppStorage("splitWidePageMode") private var splitWidePageMode: SplitWidePageMode = .none
  @AppStorage("webtoonPageWidthPercentage") private var webtoonPageWidthPercentage: Double = 100.0
  @AppStorage("webtoonTapScrollPercentage") private var webtoonTapScrollPercentage: Double = 80.0
  @AppStorage("defaultReadingDirection") private var readDirection: ReadingDirection = .ltr
  @AppStorage("forceDefaultReadingDirection") private var forceDefaultReadingDirection: Bool = false
  @AppStorage("showPageNumber") private var showPageNumber: Bool = true
  @AppStorage("showPageShadow") private var showPageShadow: Bool = AppConfig.showPageShadow
  @AppStorage("animateTapTurns") private var animateTapTurns: Bool = AppConfig.animateTapTurns
  @AppStorage("pageTransitionStyle") private var pageTransitionStyle: PageTransitionStyle = .cover
  @AppStorage("doubleTapZoomScale") private var doubleTapZoomScale: Double = 3.0
  @AppStorage("doubleTapZoomMode") private var doubleTapZoomMode: DoubleTapZoomMode = .enabled
  @AppStorage("imageUpscalingMode") private var imageUpscalingMode: ReaderImageUpscalingMode =
    AppConfig.imageUpscalingMode
  @AppStorage("imageUpscaleAutoTriggerScale") private var imageUpscaleAutoTriggerScale: Double =
    AppConfig.imageUpscaleAutoTriggerScale
  @AppStorage("imageUpscaleAlwaysMaxScreenScale")
  private var imageUpscaleAlwaysMaxScreenScale: Double =
    AppConfig.imageUpscaleAlwaysMaxScreenScale
  @AppStorage("divinaPageBorderCropMode") private var divinaPageBorderCropMode: ReaderPageBorderCropMode =
    AppConfig.divinaPageBorderCropMode
  @AppStorage("enableLiveText") private var enableLiveText: Bool = false
  @AppStorage("enableDivinaImageContextMenu")
  private var enableDivinaImageContextMenu: Bool = AppConfig.enableDivinaImageContextMenu
  @AppStorage("showDivinaControlsGradientBackground")
  private var showControlsGradientBackground: Bool =
    AppConfig.showDivinaControlsGradientBackground
  @AppStorage("showDivinaProgressBarWhileReading")
  private var showProgressBarWhileReading: Bool =
    AppConfig.showDivinaProgressBarWhileReading
  @AppStorage("shakeToOpenLiveText") private var shakeToOpenLiveText: Bool = false
  @AppStorage("divinaPreloadProfile") private var divinaPreloadProfile: ReaderPreloadProfile = .balanced

  private var forcedReadingDirection: ReadingDirection? {
    forceDefaultReadingDirection ? readDirection : nil
  }

  private var shouldShowWebtoonSpecificSettings: Bool {
    guard let forcedReadingDirection else { return true }
    return forcedReadingDirection == .webtoon
  }

  private var shouldShowPagedSpecificSettings: Bool {
    guard let forcedReadingDirection else { return true }
    return forcedReadingDirection != .webtoon
  }

  private var shouldShowTapTurnAnimation: Bool {
    shouldShowWebtoonSpecificSettings || shouldShowPagedSpecificSettings
  }

  private var shouldShowWebtoonTapNavigationSettings: Bool {
    !tapZoneMode.isDisabled && shouldShowWebtoonSpecificSettings
  }

  private var doubleTapZoomEnabled: Binding<Bool> {
    Binding(
      get: { doubleTapZoomMode.isEnabled },
      set: { newValue in
        withAnimation(.appCurve()) {
          doubleTapZoomMode = newValue ? .enabled : .disabled
        }
      }
    )
  }

  // Animated at the mutation point so only the dependent sections animate.
  private var readDirectionSelection: Binding<ReadingDirection> {
    Binding(
      get: { readDirection },
      set: { newValue in
        withAnimation(.appCurve()) { readDirection = newValue }
      }
    )
  }

  private var forceDefaultReadingDirectionSelection: Binding<Bool> {
    Binding(
      get: { forceDefaultReadingDirection },
      set: { newValue in
        withAnimation(.appCurve()) { forceDefaultReadingDirection = newValue }
      }
    )
  }

  private var tapZoneModeSelection: Binding<TapZoneMode> {
    Binding(
      get: { tapZoneMode },
      set: { newValue in
        withAnimation(.appCurve()) { tapZoneMode = newValue }
      }
    )
  }

  private var imageUpscalingModeSelection: Binding<ReaderImageUpscalingMode> {
    Binding(
      get: { imageUpscalingMode },
      set: { newValue in
        withAnimation(.appCurve()) { imageUpscalingMode = newValue }
      }
    )
  }

  // The caption under the picker swaps with the selection.
  private var pageTransitionStyleSelection: Binding<PageTransitionStyle> {
    Binding(
      get: { pageTransitionStyle },
      set: { newValue in
        withAnimation(.appCurve()) { pageTransitionStyle = newValue }
      }
    )
  }

  var body: some View {
    Form {
      Section(header: Text("Default Reading Options")) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Preferred Direction", selection: readDirectionSelection) {
            ForEach(ReadingDirection.availableCases, id: \.self) { direction in
              Label(direction.displayName, systemImage: direction.icon)
                .tag(direction)
            }
          }
          .pickerStyle(.menu)
          Text("Used when a book or series doesn't specify a reading direction")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Toggle(isOn: forceDefaultReadingDirectionSelection) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Force Default Reading Direction")
            Text("Ignore book and series metadata and always use the preferred direction")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Picker("Page Layout", selection: $pageLayout) {
            ForEach(PageLayout.allCases, id: \.self) { mode in
              Label(mode.displayName, systemImage: mode.icon)
                .tag(mode)
            }
          }
          .pickerStyle(.menu)
          Text(pageLayout.detailText)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        if pageLayout == .single || pageLayout == .auto {
          VStack(alignment: .leading, spacing: 8) {
            Picker("Split Wide Pages", selection: $splitWidePageMode) {
              ForEach(SplitWidePageMode.allCases, id: \.self) { mode in
                Label(mode.displayName, systemImage: mode.icon).tag(mode)
              }
            }
            .pickerStyle(.menu)
            Text(
              "In single page mode, split landscape pages into two separate pages; Scroll keeps a spread whole and pans across it"
            )
            .font(.caption)
            .foregroundColor(.secondary)
          }
        }

        if pageLayout.supportsDualPageOptions {
          Toggle(isOn: $isolateCoverPage) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Isolate Cover Page")
              Text("Display the cover page separately, not paired with the next page")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }

      Section(header: Text("Appearance")) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Reader Background", selection: $readerBackground) {
            ForEach(ReaderBackground.allCases, id: \.self) { background in
              Text(background.displayName).tag(background)
            }
          }
          .pickerStyle(.menu)
          Text("The background color of the reader")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Toggle(isOn: $showPageNumber) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Show Page Number")
            Text("Display page number overlay on images while reading")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Toggle(isOn: $showPageShadow) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Show Page Shadow")
            Text("Render a subtle shadow around pages. Turn off for seamless dual-page spreads.")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Toggle(isOn: $showControlsGradientBackground) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Controls Gradient Background")
            Text("Add a gradient behind reader controls for better contrast over pages.")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Toggle(isOn: $showProgressBarWhileReading) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Show Progress Bar While Reading")
            Text("Keep book progress pinned to the bottom until reader controls are shown.")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        #if os(iOS) || os(macOS)
          if shouldShowWebtoonSpecificSettings {
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
              Text("Adjust the width of webtoon pages as a percentage of screen width")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        #endif
      }

      Section(header: Text("Page Turn")) {
        if shouldShowPagedSpecificSettings {
          VStack(alignment: .leading, spacing: 8) {
            Picker("Page Transition Style", selection: pageTransitionStyleSelection) {
              ForEach(PageTransitionStyle.availableCases, id: \.self) { style in
                Text(style.displayName).tag(style)
              }
            }
            .pickerStyle(.menu)
            Text(pageTransitionStyle.description)
              .font(.caption)
              .foregroundColor(.secondary)
          }

        }

        #if os(iOS) || os(macOS)
          if shouldShowTapTurnAnimation {
            Toggle(isOn: $animateTapTurns) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Animate Page Turns")
                Text("Use animation when tapping zones to turn pages")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        #endif

        Toggle(isOn: $showKeyboardHelpOverlay) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Auto-Show Keyboard Help")
            Text("Briefly show keyboard shortcuts when opening the reader")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        #if os(iOS) || os(macOS)
          VStack(alignment: .leading, spacing: 8) {
            TapZoneModePicker(
              selection: tapZoneModeSelection,
              tapZoneInversionMode: tapZoneInversionMode,
              readingDirection: readDirection
            )
            Text("Choose how tap zones are laid out")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          if !tapZoneMode.isDisabled {
            VStack(alignment: .leading, spacing: 8) {
              Picker("Tap Zone Mirroring", selection: $tapZoneInversionMode) {
                ForEach(TapZoneInversionMode.allCases, id: \.self) { mode in
                  Text(mode.displayName).tag(mode)
                }
              }
              .pickerStyle(.menu)
              Text("Mirror left and right tap zones manually or automatically for RTL reading")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Toggle(isOn: $showTapZoneHints) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Show Tap Zone Hints")
                Text("Display tap zone hints when opening the reader")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }

            if shouldShowWebtoonTapNavigationSettings {
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
                Text("Scroll distance when tapping to navigate in webtoon mode")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        #endif
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
              Text("Zoom level when double-tapping on a page")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      #endif

      Section(header: Text("Performance")) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Image Preloading", selection: $divinaPreloadProfile) {
            ForEach(ReaderPreloadProfile.allCases) { profile in
              Text(profile.displayName).tag(profile)
            }
          }
          .pickerStyle(.menu)
          Text(divinaPreloadProfile.description)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      #if os(iOS) || os(macOS)
        Section(header: Text("Image Processing")) {
          VStack(alignment: .leading, spacing: 8) {
            Picker("Border Cropping", selection: $divinaPageBorderCropMode) {
              ForEach(ReaderPageBorderCropMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
              }
            }
            .pickerStyle(.menu)
            Text("Automatically trim empty page borders.")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          VStack(alignment: .leading, spacing: 8) {
            Picker("Waifu2x Mode", selection: imageUpscalingModeSelection) {
              ForEach(ReaderImageUpscalingMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
              }
            }
            .pickerStyle(.menu)

            Text("Improve clarity for low-resolution pages using built-in waifu2x (2x).")
              .font(.caption)
              .foregroundColor(.secondary)
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
                Text("Auto scale only when required scale to fit the page on screen is greater than this value.")
                  .font(.caption)
                  .foregroundColor(.secondary)
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
                Text("In Always mode, upscale unless source width or height exceeds this multiple of the screen.")
                  .font(.caption)
                  .foregroundColor(.secondary)
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
            VStack(alignment: .leading, spacing: 4) {
              Text("Enable Live Text")
              Text("Automatically enable Live Text for all images.")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          #if os(iOS)
            Toggle(isOn: $shakeToOpenLiveText) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Shake to Open Live Text")
                Text("Shake your device to toggle Live Text")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          #endif
        }
      #endif

      #if os(iOS) || os(macOS)
        Section(header: Text("Context Menu")) {
          Toggle(isOn: $enableDivinaImageContextMenu) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Enable Image Context Menu")
              Text(
                "Show a context menu on page images for quick actions like share or isolate page. On iOS, Live Text keeps the long-press gesture while it is enabled."
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }
          }
        }
      #endif

    }
    .formStyle(.grouped)
    .settingsFormWidth()
    .platformNavigationTitle(SettingsSection.divinaReader.title)
  }

}
