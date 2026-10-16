//
// UIPanGestureRecognizer+HorizontalDrag.swift
//
//

#if os(iOS) || os(tvOS)
  import UIKit

  extension UIPanGestureRecognizer {
    /// Horizontal distance of the drag in `view` when it's mostly horizontal,
    /// else nil. Before the pan has moved, the velocity stands in for the
    /// translation. A whole spread's scroll view and the engines' page-turn
    /// gestures all judge a drag by this, so each drag goes to exactly one.
    func horizontalDrag(in view: UIView?) -> CGFloat? {
      let translation = translation(in: view)
      let drag = translation == .zero ? velocity(in: view) : translation
      return abs(drag.x) > abs(drag.y) ? drag.x : nil
    }
  }
#endif
