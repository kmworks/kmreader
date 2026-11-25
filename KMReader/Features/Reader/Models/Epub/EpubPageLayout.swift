enum EpubPageLayout: Equatable {
  case loading
  case content(pageCount: Int)
  case failed

  var pageCount: Int? {
    switch self {
    case .loading: nil
    case .content(let count): max(1, count)
    case .failed: 1
    }
  }

  var isContent: Bool {
    if case .content = self { return true }
    return false
  }
}
