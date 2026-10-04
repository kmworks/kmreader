//
// SettingsDashboardView.swift
//
//

import SwiftUI

#if os(macOS)
  import UniformTypeIdentifiers
#endif

struct SettingsDashboardView: View {
  var body: some View {
    #if os(tvOS)
      SettingsDashboardView_tvOS()
    #elseif os(macOS)
      SettingsDashboardView_macOS()
    #else
      SettingsDashboardView_iOS()
    #endif
  }
}

#if os(iOS)
  private struct SettingsDashboardView_iOS: View {
    @AppStorage("dashboard") private var dashboard: DashboardConfiguration =
      DashboardConfiguration()
    @Environment(\.editMode) private var editMode

    private var controller: DashboardSectionsController {
      DashboardSectionsController(dashboard: $dashboard)
    }

    private var isEditing: Bool {
      editMode?.wrappedValue.isEditing == true
    }

    var body: some View {
      List {
        Section {
          SettingsDashboardCardKindMenuToggle()
          SettingsDashboardSectionBackgroundToggle()
        }

        Section {
          ForEach(controller.sections) { section in
            HStack(spacing: 12) {
              Image(systemName: section.icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)

              Text(section.displayName)

              Spacer()

              if !isEditing {
                Toggle("", isOn: controller.sectionToggleBinding(for: section))
                  .labelsHidden()
              }
            }
          }
          .onMove(perform: controller.moveSections)
        } header: {
          Text(String(localized: "dashboard.sections"))
        } footer: {
          if isEditing {
            Text(String(localized: "dashboard.sections.footer"))
              .font(.footnote)
          }
        }

        if !controller.hiddenSections.isEmpty {
          Section {
            ForEach(controller.hiddenSections) { section in
              HStack(spacing: 12) {
                Image(systemName: section.icon)
                  .foregroundStyle(.tertiary)
                  .frame(width: 24)

                Text(section.displayName)
                  .foregroundStyle(.secondary)

                Spacer()

                Button {
                  withAnimation {
                    controller.showSection(section)
                  }
                } label: {
                  Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(section.displayName))
              }
            }
          } header: {
            Text(String(localized: "dashboard.hiddenSections"))
          }
        }

        Section {
          Button(role: .destructive) {
            withAnimation {
              controller.resetSections()
            }
          } label: {
            HStack {
              Spacer()
              Text(String(localized: "dashboard.reset"))
              Spacer()
            }
          }
        }
      }
      .optimizedListStyle()
      .platformNavigationTitle(SettingsSection.dashboard.title)
      .toolbar {
        EditButton()
      }
    }
  }
#elseif os(macOS)
  private struct SettingsDashboardView_macOS: View {
    @AppStorage("dashboard") private var dashboard: DashboardConfiguration =
      DashboardConfiguration()
    @State private var draggedSection: DashboardSection?

    private var controller: DashboardSectionsController {
      DashboardSectionsController(dashboard: $dashboard)
    }

    var body: some View {
      Form {
        Section {
          SettingsDashboardCardKindMenuToggle()
          SettingsDashboardSectionBackgroundToggle()
        }

        Section {
          VStack(spacing: 0) {
            ForEach(Array(controller.sections.enumerated()), id: \.element.id) { index, section in
              HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                  .foregroundStyle(.tertiary)
                  .frame(width: 16)

                Image(systemName: section.icon)
                  .foregroundStyle(.secondary)
                  .frame(width: 20)

                Text(section.displayName)

                Spacer()

                Toggle("", isOn: controller.sectionToggleBinding(for: section))
                  .labelsHidden()
                  .toggleStyle(.switch)
              }
              .padding(.vertical, 8)
              .padding(.horizontal, 12)
              .background(
                RoundedRectangle(cornerRadius: 6)
                  .fill(draggedSection == section ? Color.primary.opacity(0.08) : Color.clear)
              )
              .contentShape(Rectangle())
              .onDrag {
                draggedSection = section
                return NSItemProvider(object: section.id as NSString)
              }
              .onDrop(
                of: [.text],
                delegate: SectionDropDelegate(
                  section: section,
                  sections: controller.sections,
                  draggedSection: $draggedSection,
                  onMove: { from, to in
                    withAnimation {
                      controller.moveSections(IndexSet(integer: from), to)
                    }
                  }
                )
              )

              if index < controller.sections.count - 1 {
                Divider()
                  .padding(.leading, 48)
              }
            }
          }
          .padding(.vertical, 4)
        } header: {
          Text(String(localized: "dashboard.sections"))
        } footer: {
          Text(String(localized: "dashboard.sections.footer"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if !controller.hiddenSections.isEmpty {
          Section {
            VStack(spacing: 8) {
              ForEach(controller.hiddenSections) { section in
                HStack(spacing: 12) {
                  Image(systemName: section.icon)
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)

                  Text(section.displayName)
                    .foregroundStyle(.secondary)

                  Spacer()

                  Button {
                    withAnimation {
                      controller.showSection(section)
                    }
                  } label: {
                    Image(systemName: "plus.circle.fill")
                      .foregroundStyle(.green)
                      .frame(minWidth: 44, minHeight: 44)
                      .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel(Text(section.displayName))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
              }
            }
          } header: {
            Text(String(localized: "dashboard.hiddenSections"))
          }
        }

        Section {
          Button(role: .destructive) {
            withAnimation {
              controller.resetSections()
            }
          } label: {
            HStack {
              Spacer()
              Text(String(localized: "dashboard.reset"))
              Spacer()
            }
          }
        }
      }
      .formStyle(.grouped)
      .settingsFormWidth()
      .platformNavigationTitle(SettingsSection.dashboard.title)
    }
  }

  private struct SectionDropDelegate: DropDelegate {
    let section: DashboardSection
    let sections: [DashboardSection]
    @Binding var draggedSection: DashboardSection?
    let onMove: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
      draggedSection = nil
      return true
    }

    func dropEntered(info: DropInfo) {
      guard let draggedSection = draggedSection,
        draggedSection != section,
        let fromIndex = sections.firstIndex(of: draggedSection),
        let toIndex = sections.firstIndex(of: section)
      else { return }

      if fromIndex != toIndex {
        onMove(fromIndex, toIndex > fromIndex ? toIndex + 1 : toIndex)
      }
    }
  }
#elseif os(tvOS)
  private struct SettingsDashboardView_tvOS: View {
    @AppStorage("dashboard") private var dashboard: DashboardConfiguration =
      DashboardConfiguration()
    @State private var editModeValue: EditMode = .inactive
    @State private var workingSections: [DashboardSection] = []

    private var controller: DashboardSectionsController {
      DashboardSectionsController(dashboard: $dashboard)
    }

    private var activeSections: [DashboardSection] {
      editModeValue == .active ? workingSections : controller.sections
    }

    private var displayHiddenSections: [DashboardSection] {
      if editModeValue == .active {
        return DashboardSection.allCases.filter { section in
          !workingSections.contains(section) && section.isAvailable
        }
      } else {
        return controller.hiddenSections
      }
    }

    var body: some View {
      List {
        // Edit/Done Button (Top)
        Section {
          HStack {
            Spacer()
            if editModeValue == .inactive {
              Button {
                withAnimation {
                  workingSections = controller.sections
                  editModeValue = .active
                }
              } label: {
                Label(String(localized: "edit"), systemImage: "pencil.circle.fill")
              }
              .adaptiveButtonStyle(.borderedProminent)
            } else {
              Button {
                withAnimation {
                  controller.setSections(workingSections)
                  editModeValue = .inactive
                }
              } label: {
                Label(String(localized: "done"), systemImage: "checkmark.circle.fill")
              }
              .adaptiveButtonStyle(.borderedProminent)
            }
          }
        }
        .listRowBackground(Color.clear)

        Section {
          SettingsDashboardCardKindMenuToggle()
          SettingsDashboardSectionBackgroundToggle()
        }

        // Active Sections
        Section {
          ForEach(activeSections) { section in
            SectionRow(
              section: section,
              isEditMode: editModeValue == .active,
              isEnabled: true,
              onDelete: {
                withAnimation {
                  if let index = workingSections.firstIndex(of: section) {
                    workingSections.remove(at: index)
                  }
                }
              }
            )
          }
          .onMove(perform: moveItem)
        } header: {
          Text(String(localized: "dashboard.sections"))
        } footer: {
          if editModeValue == .active {
            Text(String(localized: "dashboard.sections.footer.tvos"))
          }
        }

        // Hidden Sections - Only show in Edit Mode for a cleaner UI
        if editModeValue == .active && !displayHiddenSections.isEmpty {
          Section {
            ForEach(displayHiddenSections) { section in
              HStack(spacing: 16) {
                Image(systemName: section.icon)
                  .foregroundStyle(.secondary)
                  .frame(width: 32)

                Text(section.displayName)
                  .font(.title3)
                  .foregroundStyle(.secondary)

                Spacer()

                Button {
                  withAnimation {
                    workingSections.append(section)
                  }
                } label: {
                  Image(systemName: "plus")
                    .font(.body.bold())
                }
                .buttonStyle(.bordered)
              }
              .padding(.vertical, 8)
            }
          } header: {
            Text(String(localized: "dashboard.hiddenSections"))
          }
        }

        // Reset & Done
        Section {
          Button(role: .destructive) {
            withAnimation {
              controller.resetSections()
              if editModeValue == .active {
                workingSections = controller.sections
              }
            }
          } label: {
            HStack {
              Spacer()
              Text(String(localized: "dashboard.reset"))
              Spacer()
            }
          }

          if editModeValue == .active {
            Button {
              withAnimation {
                controller.setSections(workingSections)
                editModeValue = .inactive
              }
            } label: {
              HStack {
                Spacer()
                Label(String(localized: "done"), systemImage: "checkmark.circle.fill")
                Spacer()
              }
            }
            .adaptiveButtonStyle(.borderedProminent)
          }
        }
      }
      .environment(\.editMode, $editModeValue)
      .platformNavigationTitle(SettingsSection.dashboard.title)
    }

    private func moveItem(from source: IndexSet, to destination: Int) {
      workingSections.move(fromOffsets: source, toOffset: destination)
    }
  }

  private struct SectionRow: View {
    let section: DashboardSection
    let isEditMode: Bool
    let isEnabled: Bool
    let onDelete: () -> Void

    var body: some View {
      HStack(spacing: 16) {
        Image(systemName: section.icon)
          .foregroundStyle(isEnabled ? .primary : .tertiary)
          .frame(width: 32)

        Text(section.displayName)
          .font(.title3)
          .foregroundStyle(isEnabled ? .primary : .secondary)

        Spacer()

        if isEditMode {
          Button {
            onDelete()
          } label: {
            Image(systemName: "minus")
              .font(.body.bold())
              .foregroundStyle(.red)
          }
          .buttonStyle(.bordered)
        }
      }
      .padding(.vertical, 8)
    }
  }
#endif

private struct DashboardSectionsController {
  var dashboard: Binding<DashboardConfiguration>

  var sections: [DashboardSection] {
    dashboard.wrappedValue.sections
  }

  var hiddenSections: [DashboardSection] {
    DashboardSection.allCases.filter { !isSectionVisible($0) && $0.isAvailable }
  }

  /// Section edits change only the section list; the library selection and
  /// the card kinds picked in section headers carry over.
  private func updateSections(_ newSections: [DashboardSection]) {
    var configuration = dashboard.wrappedValue
    configuration.sections = newSections
    dashboard.wrappedValue = configuration
  }

  func isSectionVisible(_ section: DashboardSection) -> Bool {
    sections.contains(section)
  }

  func hideSection(_ section: DashboardSection) {
    guard let index = sections.firstIndex(of: section) else { return }
    var newSections = sections
    newSections.remove(at: index)
    updateSections(newSections)
  }

  func showSection(_ section: DashboardSection) {
    guard !isSectionVisible(section) else { return }
    var newSections = sections
    if let referenceIndex = DashboardSection.allCases.firstIndex(of: section) {
      var insertIndex = newSections.count
      for (idx, existingSection) in newSections.enumerated() {
        if let existingIndex = DashboardSection.allCases.firstIndex(of: existingSection),
          existingIndex > referenceIndex
        {
          insertIndex = idx
          break
        }
      }
      newSections.insert(section, at: insertIndex)
    } else {
      newSections.append(section)
    }
    updateSections(newSections)
  }

  func moveSections(_ source: IndexSet, _ destination: Int) {
    var newSections = sections
    newSections.move(fromOffsets: source, toOffset: destination)
    updateSections(newSections)
  }

  func setSections(_ newSections: [DashboardSection]) {
    updateSections(newSections)
  }

  func resetSections() {
    updateSections(DashboardSection.allCases.filter(\.isAvailable))
  }

  func sectionToggleBinding(for section: DashboardSection) -> Binding<Bool> {
    Binding(
      get: { isSectionVisible(section) },
      set: { newValue in
        withAnimation {
          if newValue {
            showSection(section)
          } else {
            hideSection(section)
          }
        }
      }
    )
  }

  func hiddenSectionToggleBinding(for section: DashboardSection) -> Binding<Bool> {
    Binding(
      get: { isSectionVisible(section) },
      set: { _ in
        withAnimation {
          showSection(section)
        }
      }
    )
  }

}
