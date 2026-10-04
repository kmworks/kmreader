//
// SettingsAppearanceView.swift
//
//

import Foundation
import SwiftUI

struct SettingsAppearanceView: View {
  @AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system
  @AppStorage("privacyProtection") private var privacyProtection: Bool = false
  #if os(iOS)
    @State private var selectedAppIcon: AppIconOption = .primary
    @State private var isUpdatingAppIcon: Bool = false
  #endif

  init() {
    #if os(iOS)
      _selectedAppIcon = State(
        initialValue: AppIconOption.from(alternateIconName: UIApplication.shared.alternateIconName)
      )
    #endif
  }

  var body: some View {
    Form {
      #if os(iOS)
        Section(header: Text(String(localized: "settings.appearance.language"))) {
          Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
              UIApplication.shared.open(url)
            }
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.appearance.language.change"))
                Text(String(localized: "settings.appearance.language.caption"))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer()
              Image(systemName: "arrow.up.forward.app")
                .foregroundColor(.secondary)
            }
          }
        }

        if UIApplication.shared.supportsAlternateIcons {
          Section(header: Text(String(localized: "App Icon"))) {
            if isKnownSimulatorAlternateIconIssue {
              Text(String(localized: "settings.appearance.appIcon.simulatorIssue"))
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
              HStack(spacing: 12) {
                ForEach(AppIconOption.allCases) { option in
                  appIconButton(for: option)
                }
              }
              .padding(.vertical, 4)
              .disabled(isUpdatingAppIcon)
              .onChange(of: selectedAppIcon) { _, newValue in
                updateAppIcon(to: newValue)
              }
            }
          }
        }
      #endif

      Section(header: Text(String(localized: "settings.appearance.theme"))) {
        Picker(
          String(localized: "settings.appearance.colorScheme.title"),
          selection: $appColorScheme
        ) {
          ForEach(AppColorScheme.allCases) { scheme in
            Text(scheme.label).tag(scheme)
          }
        }
      }

      Section(header: Text(String(localized: "settings.appearance.privacy"))) {
        Toggle(isOn: $privacyProtection) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings.appearance.privacyProtection.title"))
            Text(String(localized: "settings.appearance.privacyProtection.caption"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

    }
    .formStyle(.grouped)
    .settingsFormWidth()
    .platformNavigationTitle(SettingsSection.appearance.title)
    #if os(iOS)
      .onAppear {
        selectedAppIcon = AppIconOption.from(alternateIconName: UIApplication.shared.alternateIconName)
      }
    #endif
  }

  #if os(iOS)
    private func appIconButton(for option: AppIconOption) -> some View {
      let isSelected = selectedAppIcon == option

      return Button {
        selectedAppIcon = option
      } label: {
        VStack(spacing: 4) {
          Image(option.logoAssetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          Text(option.title)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
              isSelected ? Color.primary : Color.secondary.opacity(0.2),
              lineWidth: isSelected ? 2 : 1
            )
        )
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func updateAppIcon(to option: AppIconOption) {
      guard UIApplication.shared.supportsAlternateIcons else {
        return
      }
      guard !isUpdatingAppIcon else {
        return
      }
      guard UIApplication.shared.alternateIconName != option.alternateIconName else {
        return
      }

      isUpdatingAppIcon = true
      UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
        Task { @MainActor in
          isUpdatingAppIcon = false
          guard let error else {
            return
          }

          let nsError = error as NSError
          if isKnownSimulatorAlternateIconError(nsError) {
            selectedAppIcon = AppIconOption.from(
              alternateIconName: UIApplication.shared.alternateIconName
            )
            ErrorManager.shared.notify(message: String(localized: "settings.appearance.appIcon.simulatorIssue"))
            return
          }

          AppLogger(.app).error(
            "Failed to set app icon to \(option.rawValue): \(nsError.domain) (\(nsError.code)) \(nsError.localizedDescription)"
          )
          if nsError.domain == "UIApplicationErrorDomain", nsError.code == 3072 {
            selectedAppIcon = AppIconOption.from(
              alternateIconName: UIApplication.shared.alternateIconName
            )
            return
          }

          selectedAppIcon = AppIconOption.from(
            alternateIconName: UIApplication.shared.alternateIconName
          )
          ErrorManager.shared.alert(error: error)
        }
      }
    }

    private var isKnownSimulatorAlternateIconIssue: Bool {
      #if targetEnvironment(simulator)
        if #available(iOS 26.1, *),
          !ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
        {
          return true
        }
      #endif
      return false
    }

    private func isKnownSimulatorAlternateIconError(_ error: NSError) -> Bool {
      isKnownSimulatorAlternateIconIssue
        && error.domain == NSPOSIXErrorDomain
        && error.code == POSIXErrorCode.EAGAIN.rawValue
    }
  #endif
}
