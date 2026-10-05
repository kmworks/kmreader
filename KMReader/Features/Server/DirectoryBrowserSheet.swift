//
// DirectoryBrowserSheet.swift
//
//

import SwiftUI

struct DirectoryBrowserSheet: View {
  @Binding var selectedPath: String
  @Environment(\.dismiss) private var dismiss
  @State private var directoryListing: DirectoryListingResult?
  @State private var currentPath: String = ""
  @State private var isLoading = false
  @State private var error: Error?

  var body: some View {
    SheetView(
      title: String(localized: "library.add.browse.title", defaultValue: "Select Folder"),
      size: .large,
      applyFormStyle: false
    ) {
      VStack(spacing: 0) {
        // Current path display
        HStack {
          Text(currentPath.isEmpty ? "/" : currentPath)
            .font(.footnote)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
          Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))

        if isLoading {
          Spacer()
          ProgressView()
          Spacer()
        } else if error != nil {
          Spacer()
          VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
              .font(.largeTitle)
              .foregroundColor(.orange)
            Text(formattedErrorMessage)
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
            Button(String(localized: "Retry")) {
              loadDirectory(path: currentPath)
            }
          }
          .padding()
          Spacer()
        } else if let listing = directoryListing {
          List {
            // Parent directory
            if let parent = listing.parent {
              Button {
                navigateTo(parent)
              } label: {
                HStack {
                  Image(systemName: "arrow.left")
                    .foregroundColor(.secondary)
                  Text(
                    String(localized: "library.add.browse.parent", defaultValue: "Parent Directory")
                  )
                  .foregroundColor(.primary)
                  Spacer()
                }
              }
            }

            // Directories
            ForEach(listing.directories) { item in
              Button {
                navigateTo(item.path)
              } label: {
                HStack {
                  Image(systemName: "folder")
                    .foregroundColor(.secondary)
                  Text(item.name)
                    .foregroundColor(.primary)
                  Spacer()
                  Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
              }
            }
          }
          .listStyle(.plain)
        }
      }
    } controls: {
      Button {
        selectedPath = currentPath
        dismiss()
      } label: {
        Label(String(localized: "Select"), systemImage: "checkmark")
      }
      .disabled(currentPath.isEmpty)
    }
    .task {
      loadDirectory(path: selectedPath.isEmpty ? "" : selectedPath)
    }
  }

  private var formattedErrorMessage: String {
    guard let error else { return "" }
    if let apiError = error as? APIError {
      return apiError.description
    }
    if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
      return message
    }
    return error.localizedDescription
  }

  private func navigateTo(_ path: String) {
    withAnimation {
      currentPath = path
    }
    loadDirectory(path: path)
  }

  private func loadDirectory(path: String) {
    withAnimation {
      isLoading = true
      error = nil
    }
    Task {
      do {
        let result = try await FilesystemService.getDirectoryListing(path: path)
        withAnimation {
          directoryListing = result
          // Update currentPath based on the directory we're viewing
          if path.isEmpty, result.directories.first != nil {
            // We're at root, keep path empty or use parent to determine
            currentPath = result.parent ?? path
          } else {
            currentPath = path
          }
          isLoading = false
        }
      } catch {
        withAnimation {
          self.error = error
          isLoading = false
        }
      }
    }
  }
}
