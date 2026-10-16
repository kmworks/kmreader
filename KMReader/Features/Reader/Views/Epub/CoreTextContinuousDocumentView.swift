#if os(iOS)
  import UIKit
  import YueduCoreText

  @MainActor
  final class CoreTextContinuousDocumentView: UIView {
    var document: BrowserScrollDocument? {
      didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
      guard let document, let context = UIGraphicsGetCurrentContext() else { return }
      document.items(in: rect).draw(in: context)
    }
  }
#endif
