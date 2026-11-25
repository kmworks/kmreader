import Foundation

enum EpubNavigationDestination: Equatable {
  case page(Int)
  case lastPage
  case fraction(Double)
  case fragment(String)

  func pageIndex(pageCount: Int) -> Int {
    let count = max(1, pageCount)
    switch self {
    case .page(let index): return max(0, min(count - 1, index))
    case .lastPage: return count - 1
    case .fraction(let value): return max(0, min(count - 1, Int((Double(count) * value).rounded(.down))))
    case .fragment: return 0
    }
  }

  func estimatedPageIndex(pageCount: Int) -> Int {
    if case .page(let index) = self { return max(0, index) }
    return self.pageIndex(pageCount: pageCount)
  }

  var progression: Double? {
    if case .fraction(let value) = self { return value }
    return nil
  }

  var requiresFullExtent: Bool {
    switch self {
    case .page: false
    case .lastPage, .fraction, .fragment: true
    }
  }
}
