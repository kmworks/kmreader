#if os(iOS)
  import UIKit
  import YueduCoreText

  @MainActor
  final class CoreTextDisplayListView: UIView {
    var displayList: DisplayList? {
      didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
      guard let context = UIGraphicsGetCurrentContext() else { return }
      displayList?.draw(in: context)
    }
  }
#endif
