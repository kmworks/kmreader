//
// CustomFontsSheet.swift
//
//

#if os(iOS)
  import CoreText
  import SwiftUI
  import UIKit
  import UniformTypeIdentifiers

  struct CustomFontsSheet: View {
    @State private var customFontInput: String = ""
    @State private var showFontInputError: Bool = false
    @State private var fontInputErrorMessage: String = ""
    @State private var showFontPicker: Bool = false
    @State private var showDocumentPicker: Bool = false
    @State private var customFonts: [CustomFontDisplayItem] = []

    var body: some View {
      SheetView(title: String(localized: "Custom Fonts"), size: .large, applyFormStyle: true) {
        Form {
          Section {
            Button {
              showFontPicker = true
            } label: {
              HStack {
                Label("Pick Font from System", systemImage: "textformat")
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          } header: {
            Text("System Font Picker")
          } footer: {
            Text("Select from the system preinstalled fonts")
          }

          Section {
            Button {
              showDocumentPicker = true
            } label: {
              HStack {
                Label("Import Font from Files", systemImage: "doc.badge.plus")
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          } header: {
            Text("Import Custom Font")
          } footer: {
            Text("Import .ttf or .otf font files from Files app")
          }

          Section {
            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 8) {
                TextField("Font name", text: $customFontInput)
                  .textFieldStyle(.plain)
                  .autocorrectionDisabled()
                  .textInputAutocapitalization(.never)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 10)
                  .background(.secondary.opacity(0.1))
                  .cornerRadius(10)
                  .onSubmit {
                    addCustomFont()
                  }
                Button {
                  addCustomFont()
                } label: {
                  HStack(spacing: 4) {
                    Image(systemName: AppIcon.addRow)
                    Text("Add")
                  }.foregroundStyle(.white)
                }
                .adaptiveButtonStyle(.borderedProminent)
              }
              if showFontInputError {
                Text(fontInputErrorMessage)
                  .font(.caption)
                  .foregroundStyle(.red)
              }
            }
            .padding(.vertical, 4)
          } header: {
            Text("Manual Entry")
          } footer: {
            Text(
              "To find font names, go to Settings > General > Fonts on your device. All fonts, including profile-installed fonts, are available."
            )
          }

          if !customFonts.isEmpty {
            Section {
              ForEach(customFonts) { font in
                HStack {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(font.name)
                      .font(.subheadline.monospaced())
                    if font.path != nil {
                      HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc.fill")
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                        if let fileName = font.fileName {
                          Text(fileName)
                            .font(.caption)
                            .lineLimit(1)
                        }
                        if let fileSize = font.fileSize {
                          Text("•")
                            .font(.caption)
                          Text(formatFileSize(fileSize))
                            .font(.caption2)
                            .lineLimit(1)
                        }
                      }
                      .foregroundStyle(.secondary)
                    }
                  }
                  Spacer()
                }
                .textSelectionIfAvailable()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                  Button(role: .destructive) {
                    removeCustomFont(font)
                  } label: {
                    Label("Delete", systemImage: AppIcon.delete)
                  }
                }
              }
            } header: {
              Text("Custom Fonts")
            } footer: {
              Text("\(customFonts.count) custom font added")
            }
          }
        }
      }
      .sheet(isPresented: $showFontPicker) {
        FontPickerView(isPresented: $showFontPicker) { selectedFont in
          handleFontPickerSelection(selectedFont)
        }
      }
      .sheet(isPresented: $showDocumentPicker) {
        FontDocumentPicker(isPresented: $showDocumentPicker) { url in
          handleFontFileImport(url)
        }
      }
      .task {
        await loadCustomFonts()
      }
    }

    private func handleFontPickerSelection(_ font: UIFont) {
      // Get font family name
      let familyName = font.familyName

      // Check if font already exists in custom fonts
      if customFonts.contains(where: { $0.name == familyName }) {
        // Font already added, just clear any error
        showFontInputError = false
        fontInputErrorMessage = ""
        return
      }

      Task {
        await saveCustomFont(name: familyName)
      }
    }

    private func handleFontFileImport(_ url: URL) {
      // Start accessing the security-scoped resource
      guard url.startAccessingSecurityScopedResource() else {
        showFontInputError = true
        fontInputErrorMessage = "Failed to access font file"
        return
      }
      defer { url.stopAccessingSecurityScopedResource() }

      // Get the font file name and size
      let fileName = url.lastPathComponent
      var fileSize: Int64 = 0
      do {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber {
          fileSize = size.int64Value
        }
      } catch {
        showFontInputError = true
        fontInputErrorMessage = "Failed to read font file attributes: \(error.localizedDescription)"
        return
      }

      // Copy font file to app storage using FontFileManager
      let relativePath: String
      do {
        relativePath = try FontFileManager.copyFont(from: url, fileName: fileName)
      } catch {
        showFontInputError = true
        fontInputErrorMessage = "Failed to copy font file: \(error.localizedDescription)"
        return
      }

      // Get absolute path for font registration
      guard let absolutePath = FontFileManager.resolvePath(relativePath),
        let destinationURL = URL(string: "file://\(absolutePath)")
      else {
        showFontInputError = true
        fontInputErrorMessage = "Failed to resolve font file path"
        return
      }

      // Register the font with CoreText
      guard let fontDataProvider = CGDataProvider(url: destinationURL as CFURL),
        let cgFont = CGFont(fontDataProvider)
      else {
        showFontInputError = true
        fontInputErrorMessage = "Failed to load font file"
        // Clean up the copied file
        FontFileManager.deleteFont(at: relativePath)
        return
      }

      var error: Unmanaged<CFError>?
      if !CTFontManagerRegisterGraphicsFont(cgFont, &error) {
        // Font might already be registered, which is okay
        if let error = error?.takeRetainedValue() {
          let errorDescription = CFErrorCopyDescription(error) as String
          // Only show error if it's not about the font already being registered
          if !errorDescription.contains("already registered") {
            showFontInputError = true
            fontInputErrorMessage = "Failed to register font: \(errorDescription)"
            FontFileManager.deleteFont(at: relativePath)
            return
          }
        }
      }

      // Get the actual font full name from the registered font (includes style like "Regular", "Bold")
      let ctFont = CTFontCreateWithGraphicsFont(cgFont, 12, nil, nil)
      let actualFontName = CTFontCopyFullName(ctFont) as String

      // Unregister the font immediately after getting its name (we use CSS @font-face for WKWebView)
      CTFontManagerUnregisterGraphicsFont(cgFont, nil)

      // Check if font with this full name already exists
      if customFonts.contains(where: { $0.name == actualFontName }) {
        showFontInputError = true
        fontInputErrorMessage = "Font already added"
        FontFileManager.deleteFont(at: relativePath)
        return
      }

      Task {
        await saveCustomFont(
          name: actualFontName,
          path: relativePath,
          fileName: fileName,
          fileSize: fileSize,
          cleanupPathOnFailure: relativePath
        )
      }
    }

    private func addCustomFont() {
      let fontName = customFontInput.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !fontName.isEmpty else {
        showFontInputError = true
        fontInputErrorMessage = "Font name cannot be empty"
        return
      }

      // Check if font already exists in custom fonts
      if customFonts.contains(where: { $0.name == fontName }) {
        showFontInputError = true
        fontInputErrorMessage = "Font already added"
        return
      }

      // Check if font already exists in system fonts
      if FontProvider.allChoices.contains(where: { $0.rawValue == fontName }) {
        showFontInputError = true
        fontInputErrorMessage = "Font already available in system fonts"
        return
      }

      // Verify font exists by trying to create it
      if !isFontAvailable(fontName) {
        showFontInputError = true
        fontInputErrorMessage = "Font not found. Make sure the font name is correct."
        return
      }

      Task {
        await saveCustomFont(name: fontName, clearInputOnSuccess: true)
      }
    }

    private func removeCustomFont(_ font: CustomFontDisplayItem) {
      Task {
        do {
          let database = try await DatabaseOperator.database()
          try await database.deleteCustomFont(name: font.name)
          if let relativePath = font.path {
            FontFileManager.deleteFont(at: relativePath)
          }
          await loadCustomFonts()
          FontProvider.refresh()
        } catch {
          showFontInputError = true
          fontInputErrorMessage = "Failed to delete font: \(error.localizedDescription)"
        }
      }
    }

    private func isFontAvailable(_ fontName: String) -> Bool {
      // Try to create a UIFont with the name
      if let font = UIFont(name: fontName, size: 12) {
        return font.familyName == fontName || font.fontName == fontName
      }
      // Also try with CTFont (always succeeds, but we check the family name)
      let ctFont = CTFontCreateWithName(fontName as CFString, 12, nil)
      let familyName = CTFontCopyFamilyName(ctFont) as String?
      if let familyName = familyName, familyName == fontName {
        return true
      }
      // Try PostScript name as well
      let postScriptName = CTFontCopyPostScriptName(ctFont) as String?
      if let postScriptName = postScriptName, postScriptName == fontName {
        return true
      }
      return false
    }

    private func formatFileSize(_ bytes: Int64) -> String {
      let formatter = ByteCountFormatter()
      formatter.allowedUnits = [.useKB, .useMB]
      formatter.countStyle = .file
      return formatter.string(fromByteCount: bytes)
    }

    private func saveCustomFont(
      name: String,
      path: String? = nil,
      fileName: String? = nil,
      fileSize: Int64? = nil,
      clearInputOnSuccess: Bool = false,
      cleanupPathOnFailure: String? = nil
    ) async {
      do {
        let database = try await DatabaseOperator.database()
        try await database.createCustomFont(
          name: name,
          path: path,
          fileName: fileName,
          fileSize: fileSize
        )

        if clearInputOnSuccess {
          customFontInput = ""
        }
        showFontInputError = false
        fontInputErrorMessage = ""
        await loadCustomFonts()
        FontProvider.refresh()
      } catch {
        if let cleanupPathOnFailure {
          FontFileManager.deleteFont(at: cleanupPathOnFailure)
        }
        showFontInputError = true
        fontInputErrorMessage = "Failed to save font: \(error.localizedDescription)"
      }
    }

    private func loadCustomFonts() async {
      do {
        let database = try await DatabaseOperator.database()
        let loadedFonts = try await database.fetchCustomFontDisplayItems()
        if customFonts != loadedFonts {
          customFonts = loadedFonts
        }
      } catch {
        showFontInputError = true
        fontInputErrorMessage = "Failed to load fonts: \(error.localizedDescription)"
      }
    }
  }

  struct FontPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onFontSelected: (UIFont) -> Void

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
      let picker = UIFontPickerViewController()
      picker.delegate = context.coordinator
      return picker
    }

    func updateUIViewController(_ uiViewController: UIFontPickerViewController, context: Context) {
      context.coordinator.isPresented = $isPresented
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(isPresented: $isPresented, onFontSelected: onFontSelected)
    }

    class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
      var isPresented: Binding<Bool>
      let onFontSelected: (UIFont) -> Void

      init(isPresented: Binding<Bool>, onFontSelected: @escaping (UIFont) -> Void) {
        self.isPresented = isPresented
        self.onFontSelected = onFontSelected
      }

      func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
        guard let selectedFontDescriptor = viewController.selectedFontDescriptor else {
          return
        }

        // Create a font from the descriptor
        let font = UIFont(descriptor: selectedFontDescriptor, size: 12)
        onFontSelected(font)

        // Dismiss the picker
        DispatchQueue.main.async {
          self.isPresented.wrappedValue = false
        }
      }
    }
  }

  struct FontDocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onFontSelected: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
      let contentTypes: [UTType] = {
        let types = ["ttf", "otf"].compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.font] : types
      }()
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
      picker.delegate = context.coordinator
      picker.allowsMultipleSelection = false
      return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
      context.coordinator.isPresented = $isPresented
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(isPresented: $isPresented, onFontSelected: onFontSelected)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
      var isPresented: Binding<Bool>
      let onFontSelected: (URL) -> Void

      init(isPresented: Binding<Bool>, onFontSelected: @escaping (URL) -> Void) {
        self.isPresented = isPresented
        self.onFontSelected = onFontSelected
      }

      func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        onFontSelected(url)

        // Dismiss the picker
        DispatchQueue.main.async {
          self.isPresented.wrappedValue = false
        }
      }

      func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        DispatchQueue.main.async {
          self.isPresented.wrappedValue = false
        }
      }
    }
  }
#endif
