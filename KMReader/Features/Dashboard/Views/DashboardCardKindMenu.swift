//
// DashboardCardKindMenu.swift
//
//

import SwiftUI

/// Section header menu that switches a dashboard section between the card
/// kinds it offers. Renders nothing for a section with a single kind.
struct DashboardCardKindMenu: View {
  let section: DashboardSection

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("showDashboardCardKindMenu") private var showDashboardCardKindMenu: Bool = true

  private var cardKindBinding: Binding<DashboardCardKind> {
    Binding(
      get: { dashboard.cardKind(for: section) },
      set: { dashboard.setCardKind($0, for: section) }
    )
  }

  var body: some View {
    if showDashboardCardKindMenu && section.availableCardKinds.count > 1 {
      Menu {
        Picker(selection: cardKindBinding) {
          ForEach(section.availableCardKinds, id: \.self) { kind in
            Label(kind.title, systemImage: kind.icon).tag(kind)
          }
        } label: {
          EmptyView()
        }
        .pickerStyle(.inline)
        .labelsHidden()
      } label: {
        Image(systemName: "rectangle.3.group")
          .foregroundStyle(.secondary)
          .frame(minWidth: 28, minHeight: 28)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(Text(String(localized: "settings.dashboard.cardKindMenu.title")))
    }
  }
}
