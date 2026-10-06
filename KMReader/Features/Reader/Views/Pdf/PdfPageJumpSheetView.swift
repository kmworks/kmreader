#if os(iOS) || os(macOS)
  import PDFKit
  import SwiftUI

  struct PdfPageJumpSheetView: View {
    let documentURL: URL
    let totalPages: Int
    let currentPage: Int
    let readingDirection: ReadingDirection
    let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pageValue: Int
    @State private var scrollPosition: Int?
    @State private var document: PDFDocument?
    @State private var thumbnails: [Int: PlatformImage] = [:]
    @State private var currentDocumentKey: String = ""

    private var maxPage: Int {
      max(totalPages, 1)
    }

    private var documentKey: String {
      documentURL.standardizedFileURL.path
    }

    private var canJump: Bool {
      totalPages > 0
    }

    private var sliderScaleX: CGFloat {
      readingDirection == .rtl ? -1 : 1
    }

    private var pageLabels: (left: String, right: String) {
      if readingDirection == .rtl {
        return (left: "\(totalPages)", right: "1")
      }
      return (left: "1", right: "\(totalPages)")
    }

    private var sliderBinding: Binding<Double> {
      Binding(
        get: { Double(pageValue) },
        set: { newValue in
          let newPage = Int(newValue.rounded())
          if newPage != pageValue {
            pageValue = newPage
          }
        }
      )
    }

    init(
      documentURL: URL,
      totalPages: Int,
      currentPage: Int,
      readingDirection: ReadingDirection,
      onJump: @escaping (Int) -> Void
    ) {
      self.documentURL = documentURL
      self.totalPages = totalPages
      self.currentPage = currentPage
      self.readingDirection = readingDirection
      self.onJump = onJump
      let safeInitialPage = max(1, min(currentPage, max(totalPages, 1)))
      _pageValue = State(initialValue: safeInitialPage)
      _scrollPosition = State(initialValue: safeInitialPage)
    }

    private func jumpToPage() {
      guard canJump else { return }
      let clampedValue = min(max(pageValue, 1), totalPages)
      onJump(clampedValue)
      dismiss()
    }

    private func loadDocumentIfNeeded() {
      if document == nil || currentDocumentKey != documentKey {
        document = PDFDocument(url: documentURL)
        currentDocumentKey = documentKey
        thumbnails.removeAll()
      }
    }

    private func loadThumbnail(for page: Int, targetHeight: CGFloat) {
      guard thumbnails[page] == nil else { return }
      loadDocumentIfNeeded()
      guard let document else { return }
      guard let pdfPage = document.page(at: page - 1) else { return }

      let targetWidth = max(48, targetHeight * PageJumpPreviewCard.widthRatio)
      let thumbnail = pdfPage.thumbnail(
        of: CGSize(width: targetWidth, height: targetHeight),
        for: .mediaBox
      )
      thumbnails[page] = thumbnail
    }

    var body: some View {
      SheetView(title: String(localized: "Go to Page"), size: .medium) {
        VStack(spacing: 16) {
          if canJump {
            Text("Current page: \(currentPage)")
              .foregroundStyle(.secondary)

            VStack(spacing: 16) {
              GeometryReader { geometry in
                let imageHeight = min(geometry.size.height - 40, 250)
                let imageWidth = max(48, imageHeight * PageJumpPreviewCard.widthRatio)

                ScrollViewReader { proxy in
                  ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                      ForEach(1...maxPage, id: \.self) { page in
                        PageJumpPreviewCard(
                          displayPage: page,
                          image: thumbnails[page],
                          isSelected: page == pageValue,
                          imageHeight: imageHeight
                        )
                        .id(page)
                        .onTapGesture {
                          pageValue = page
                          scrollPosition = page
                        }
                        .task(id: "\(documentKey)-\(page)-\(Int(imageHeight))") {
                          loadThumbnail(for: page, targetHeight: imageHeight)
                        }
                      }
                    }
                    .scrollTargetLayout()
                  }
                  .contentMargins(
                    .horizontal,
                    max(0, (geometry.size.width - imageWidth) / 2),
                    for: .scrollContent
                  )
                  .scrollClipDisabled()
                  .scrollTargetBehavior(.viewAligned)
                  .scrollPosition(id: $scrollPosition, anchor: .center)
                  .environment(
                    \.layoutDirection,
                    readingDirection == .rtl ? .rightToLeft : .leftToRight
                  )
                  .onAppear {
                    loadDocumentIfNeeded()
                    proxy.scrollTo(pageValue, anchor: .center)
                  }
                  .onChange(of: documentURL) { _, _ in
                    loadDocumentIfNeeded()
                  }
                  .onChange(of: scrollPosition) { _, newValue in
                    if let page = newValue {
                      pageValue = page
                    }
                  }
                  .onChange(of: pageValue) { _, newValue in
                    if scrollPosition != newValue {
                      withAnimation(.appSpring) {
                        proxy.scrollTo(newValue, anchor: .center)
                      }
                    }
                  }
                }
              }
              .frame(minHeight: 200, maxHeight: 320)

              VStack(spacing: 0) {
                Slider(
                  value: sliderBinding,
                  in: 1...Double(maxPage),
                  step: 1
                )
                .scaleEffect(x: sliderScaleX, y: 1)

                HStack {
                  Text(pageLabels.left)
                  Spacer()
                  Text(pageLabels.right)
                }
                .foregroundStyle(.secondary)
              }

              HStack {
                Button {
                  jumpToPage()
                } label: {
                  HStack(spacing: 4) {
                    Text("Jump")
                    Image(systemName: AppIcon.pageJump)
                  }
                }
                .adaptiveButtonStyle(.borderedProminent)
                .disabled(!canJump || pageValue == currentPage)
              }
            }
          } else {
            Text(String(localized: "No pages available."))
              .foregroundStyle(.secondary)
          }

          Spacer()
        }
        .padding()
      }
      .presentationDragIndicator(.visible)
    }
  }
#endif
