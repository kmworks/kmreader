//
// MangaToolsSheetsModifier.swift
//
//

import SwiftUI

/// Presents `MangaToolsSettingsModel.sheet`. Apply it to the Form, never to a
/// section inside it.
struct MangaToolsSheetsModifier: ViewModifier {
  @Bindable var model: MangaToolsSettingsModel

  func body(content: Content) -> some View {
    content
      .onAppear(perform: model.reload)
      .sheet(item: $model.sheet, onDismiss: model.reload) { sheet in
        switch sheet {
        case .providers:
          SheetView(title: String(localized: "Translation Providers"), size: .large, applyFormStyle: true) {
            MangaProviderManagementView()
          }
        case .model(let role):
          SheetView(title: role.title, size: .large, applyFormStyle: true) {
            MangaModelManagementView(role: role)
          }
        #if os(iOS)
          case .panelModel:
            SheetView(title: String(localized: "Panel Mode Model"), size: .large, applyFormStyle: true) {
              PanelModelManagementView()
            }
        #endif
        }
      }
  }
}

extension View {
  func mangaToolsSheets(model: MangaToolsSettingsModel) -> some View {
    modifier(MangaToolsSheetsModifier(model: model))
  }
}
