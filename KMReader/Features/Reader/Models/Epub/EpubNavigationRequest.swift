import Foundation

struct EpubNavigationRequest: Equatable {
  let id: UUID
  let chapterIndex: Int
  let destination: EpubNavigationDestination
  let restoresRemoteProgress: Bool

  init(id: UUID, chapterIndex: Int, destination: EpubNavigationDestination, restoresRemoteProgress: Bool = false) {
    self.id = id
    self.chapterIndex = chapterIndex
    self.destination = destination
    self.restoresRemoteProgress = restoresRemoteProgress
  }
}
