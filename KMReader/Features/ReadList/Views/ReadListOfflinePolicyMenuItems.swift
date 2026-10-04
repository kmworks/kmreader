//
// ReadListOfflinePolicyMenuItems.swift
//
//

import SwiftUI

/// Offline-policy menu entries (manual / unread-only with limit presets / all),
/// shared by the read-list context menu and the detail-page actions section.
struct ReadListOfflinePolicyMenuItems: View {
  let policy: OfflinePolicy
  let offlinePolicyLimit: Int
  let actions: ReadListOfflineActions

  var body: some View {
    Button {
      actions.updatePolicy(.manual)
    } label: {
      offlinePolicyLabel(.manual)
    }

    Menu {
      ForEach(ReadListOfflineActions.limitPresets, id: \.self) { value in
        Button {
          actions.updatePolicyAndLimit(.unreadOnly, limit: value)
        } label: {
          limitOptionLabel(policy: .unreadOnly, limit: value)
        }
      }
    } label: {
      offlinePolicyLabel(.unreadOnly)
    }

    Button {
      actions.updatePolicy(.all)
    } label: {
      offlinePolicyLabel(.all)
    }
  }

  @ViewBuilder
  private func offlinePolicyLabel(_ value: OfflinePolicy) -> some View {
    let title = value.title(limit: offlinePolicyLimit)
    Label {
      HStack(spacing: 4) {
        Text(value == policy ? title : value.label)
        if value == policy {
          Image(systemName: "checkmark")
        }
      }
    } icon: {
      Image(systemName: value.icon)
    }
  }

  @ViewBuilder
  private func limitOptionLabel(policy value: OfflinePolicy, limit: Int) -> some View {
    let title = OfflinePolicy.limitTitle(limit)
    if policy == value && offlinePolicyLimit == limit {
      Label(title, systemImage: "checkmark")
    } else {
      Text(title)
    }
  }
}
