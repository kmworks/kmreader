//
// DownloadProgressPie.swift
//
//

import SwiftUI

/// Live download progress as the Apple Books-style ring+pie, for card/row status
/// slots. The book's progress comes from DownloadProgressTracker; a 0 renders as
/// the minimum sliver so a queued download already reads as in-flight.
struct DownloadProgressPie: View {
  let progress: Double
  var color: Color = .secondary

  var body: some View {
    CircularProgressPieRepresentable(progress: progress, color: color)
  }
}

#if os(iOS) || os(tvOS)
  private struct CircularProgressPieRepresentable: UIViewRepresentable {
    let progress: Double
    let color: Color

    func makeUIView(context: Context) -> CircularProgressView {
      let view = CircularProgressView()
      view.color = UIColor(color)
      return view
    }

    func updateUIView(_ uiView: CircularProgressView, context: Context) {
      uiView.progress = progress
      uiView.color = UIColor(color)
    }
  }
#else
  private struct CircularProgressPieRepresentable: NSViewRepresentable {
    let progress: Double
    let color: Color

    func makeNSView(context: Context) -> CircularProgressView {
      let view = CircularProgressView()
      view.color = NSColor(color)
      return view
    }

    func updateNSView(_ nsView: CircularProgressView, context: Context) {
      nsView.progress = progress
      nsView.color = NSColor(color)
    }
  }
#endif
