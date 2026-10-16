#if os(iOS) || os(macOS)
  import SwiftUI

  struct PdfSearchSheetView: View {
    @Binding var query: String
    let isSearching: Bool
    let results: [PdfSearchResult]
    let onSearch: (String) -> Void
    let onSelectResult: (PdfSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss

    private var trimmedQuery: String {
      query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
      SheetView(title: String(localized: "Search"), size: .large) {
        List {
          if isSearching {
            Section {
              ContentUnavailableView {
                VStack(spacing: 8) {
                  ProgressView()
                  Text(String(localized: "Searching..."))
                    .foregroundStyle(.secondary)
                }
              }
              .listRowBackground(Color.clear)
            }
          } else if trimmedQuery.isEmpty {
            Section {
              ContentUnavailableView {
                Label(String(localized: "Search in PDF"), systemImage: AppIcon.search)
              }
              .listRowBackground(Color.clear)
            }
          } else if results.isEmpty {
            Section {
              ContentUnavailableView {
                Label(String(localized: "No matches found"), systemImage: "text.magnifyingglass")
              }
              .listRowBackground(Color.clear)
            }
          } else {
            Section {
              ForEach(results) { result in
                Button {
                  onSelectResult(result)
                  dismiss()
                } label: {
                  VStack(alignment: .leading, spacing: 6) {
                    Text("Page \(result.pageNumber)")
                      .font(.headline)
                      .foregroundStyle(.primary)
                    Text(result.snippet)
                      .font(.subheadline)
                      .foregroundStyle(.secondary)
                      .multilineTextAlignment(.leading)
                      .lineLimit(3)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
              }
            } header: {
              Text("\(results.count) results")
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
      } controls: {
        Button {
          onSearch(trimmedQuery)
        } label: {
          Label(String(localized: "Search"), systemImage: AppIcon.search)
        }
        .disabled(trimmedQuery.isEmpty)
      }
      .searchable(text: $query, prompt: String(localized: "Search in PDF"))
      .onSubmit(of: .search) {
        onSearch(trimmedQuery)
      }
      .onChange(of: query) { _, newValue in
        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          onSearch("")
        }
      }
      .presentationDragIndicator(.visible)
    }
  }
#endif
