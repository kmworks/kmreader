//
// ServerRowView.swift
//
//

import SwiftUI

struct ServerRowView: View {
  let instance: ServerDisplayItem

  @Environment(\.colorScheme) private var colorScheme

  let isGlobalSwitching: Bool
  let isSwitching: Bool
  let isActive: Bool
  let onSelect: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    Button {
      onSelect()
    } label: {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 12) {
          serverAvatar
          VStack(alignment: .leading, spacing: 4) {
            Text(instance.displayName)
              .font(.headline)
              .foregroundStyle(.primary)
            Text(instance.serverURL)
              .font(.footnote)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          statusView
        }

        Divider()
          .opacity(0.15)

        VStack(alignment: .leading, spacing: 10) {
          infoDetailRow(icon: "envelope.fill", text: instance.username)
          infoDetailRow(
            icon: instance.isAdmin ? "shield.checkered" : "shield.fill",
            text: instance.isAdmin
              ? String(localized: "Admin Access") : String(localized: "User Access"),
            textColor: instance.isAdmin ? .green : .secondary
          )
          infoDetailRow(
            icon: "key.fill",
            text: instance.authMethod == .apiKey
              ? String(localized: "API Key") : String(localized: "Username & Password"),
            textColor: .secondary
          )
          if instance.protected {
            infoDetailRow(
              icon: "lock.fill",
              text: String(localized: "Protected"),
              textColor: .orange,
              iconColor: .orange
            )
          }
          infoDetailRow(
            icon: "clock.arrow.circlepath", text: lastUsedDescription,
            textColor: .secondary)
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(cardBackground)
    }
    .adaptiveButtonStyle(.plain)
    .allowsHitTesting(!(isActive || isGlobalSwitching))
    .animation(.appCurve(), value: isActive)
    #if os(iOS) || os(macOS)
      .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
      .listRowSeparator(.hidden)
    #endif
    #if os(iOS) || os(macOS)
      .swipeActions(edge: .trailing) {
        if !isActive {
          Button {
            onEdit()
          } label: {
            Label(String(localized: "Edit"), systemImage: AppIcon.edit)
          }

          Button(role: .destructive) {
            onDelete()
          } label: {
            Label(String(localized: "Delete"), systemImage: AppIcon.delete)
          }
        }
      }
    #endif
    .contextMenu {
      if !isActive {
        Button {
          onEdit()
        } label: {
          Label(String(localized: "Edit"), systemImage: AppIcon.edit)
        }

        Button(role: .destructive) {
          onDelete()
        } label: {
          Label(String(localized: "Delete"), systemImage: AppIcon.delete)
        }
      }
    }
  }

  @ViewBuilder
  private var statusView: some View {
    if isSwitching {
      ProgressView()
        .scaleEffect(0.85)
    } else if isActive {
      infoTag(
        icon: "checkmark.seal.fill", text: LocalizedStringKey("Active"), tint: .serverGreen)
    } else {
      Image(systemName: "chevron.right")
        .font(.body.weight(.semibold))
        .foregroundStyle(.secondary)
    }
  }

  private func infoTag(
    icon: String,
    text: LocalizedStringKey,
    tint: Color = .secondary,
    fillOpacity: Double = 0.16
  ) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
      Text(text)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(tint)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(
      Capsule(style: .continuous)
        .fill(tint.opacity(fillOpacity))
    )
  }

  private func infoDetailRow(
    icon: String,
    text: String,
    textColor: Color = .primary,
    iconColor: Color = .secondary
  ) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(iconColor)
        .frame(width: 16)
      Text(text)
        .font(.footnote)
        .foregroundStyle(textColor)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var serverAvatar: some View {
    let gradientColors: [Color]
    if isActive {
      gradientColors = [
        Color.serverGreenGradientStart,
        Color.serverGreenGradientEnd,
      ]
    } else if colorScheme == .dark {
      gradientColors = [
        Color.white.opacity(0.12),
        Color.white.opacity(0.05),
      ]
    } else {
      gradientColors = [
        Color.black.opacity(0.08),
        Color.black.opacity(0.02),
      ]
    }

    return ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .overlay(
          Circle()
            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.2), lineWidth: 1)
        )

      Image(systemName: instance.isAdmin ? "crown.fill" : "server.rack")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(isActive ? Color.white : Color.primary)
    }
    .frame(width: 46, height: 46)
  }

  private var lastUsedDescription: String {
    let relativeText = instance.lastUsedAt.formatted(
      .relative(presentation: .named, unitsStyle: .abbreviated))
    return String(localized: "Last used \(relativeText)")
  }

  private var cardBackground: some View {
    let inactiveTop = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    let inactiveBottom =
      colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
    let colors =
      isActive
      ? [
        Color.serverGreen.opacity(0.12),
        Color.serverGreen.opacity(0.06),
      ]
      : [
        inactiveTop,
        inactiveBottom,
      ]

    return RoundedRectangle(cornerRadius: 22, style: .continuous)
      .fill(
        LinearGradient(
          colors: colors,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .strokeBorder(
            isActive ? Color.serverGreen.opacity(0.35) : Color.primary.opacity(0.05),
            lineWidth: isActive ? 2 : 1
          )
      )
      .shadow(
        color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
        radius: isActive ? 12 : 6,
        x: 0,
        y: isActive ? 6 : 3
      )
  }
}
