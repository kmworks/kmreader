import SwiftUI

struct MangaModelCapabilityChips: View {
  let archive: ModelArchive

  private var roles: [MangaModelRole] {
    MangaModelRole.supported(by: archive)
  }

  var body: some View {
    if !roles.isEmpty {
      HStack {
        ForEach(roles) { role in
          DetailChip(role.title, glass: false)
        }
      }
    }
  }
}
