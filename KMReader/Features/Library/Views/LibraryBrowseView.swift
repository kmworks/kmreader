//
// LibraryBrowseView.swift
//
//

import SwiftUI

/// iPhone Library tab root: content-first browsing (Apple Books style) over the
/// global library selection (dashboard.libraryIds, shared with Home). The
/// leading toolbar button is the shared LibraryScopeToolbarButton, always
/// shown; the sheet and the library list live here.
/// Library management stays in Settings.
struct LibraryBrowseView: View {
  let authViewModel: AuthViewModel

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var libraries: [SidebarLibraryItem] = []
  @State private var showLibraryPicker = false

  var body: some View {
    BrowseView(authViewModel: authViewModel, libraryTab: true)
      #if os(iOS)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            LibraryScopeToolbarButton(libraries: libraries, isPresented: $showLibraryPicker)
          }
        }
      #endif
      .sheet(isPresented: $showLibraryPicker) {
        LibraryPickerSheet()
      }
      .task(id: current.instanceId) {
        await refreshLibraries()
      }
      .onReceive(NotificationCenter.default.publisher(for: .sidebarProjectionDidChange)) { notification in
        guard notification.userInfo?["instanceId"] as? String == current.instanceId else { return }
        Task {
          await loadLibraries()
        }
      }
  }

  private func refreshLibraries() async {
    do {
      let loaded = try await LibraryScopeLoader.refresh(instanceId: current.instanceId)
      if libraries != loaded {
        libraries = loaded
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func loadLibraries() async {
    do {
      let loaded = try await LibraryScopeLoader.load(instanceId: current.instanceId)
      if libraries != loaded {
        libraries = loaded
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
