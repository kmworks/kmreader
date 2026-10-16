//
// PageCurlControllerIdentity.swift
//

#if os(iOS)
  import Foundation

  final class PageCurlControllerIdentity: NSObject {
    enum Role {
      case content
      case backside
      case placeholder
    }

    let item: ReaderViewItem?
    let role: Role
    let slot: Int?

    init(item: ReaderViewItem?, role: Role, slot: Int? = nil) {
      self.item = item
      self.role = role
      self.slot = slot
    }
  }
#endif
