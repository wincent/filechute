import FilechuteCore
import SwiftUI

enum NavigationSection: Hashable {
  case allItems
  case trash

  var title: String {
    switch self {
    case .allItems: "All Items"
    case .trash: "Trash"
    }
  }

  var icon: String {
    switch self {
    case .allItems: "tray.full"
    case .trash: "trash"
    }
  }
}

struct SidebarView: View {
  var storeManager: StoreManager
  @Binding var selection: NavigationSection?

  var body: some View {
    List(selection: $selection) {
      ForEach([NavigationSection.allItems, .trash], id: \.self) { section in
        Label(section.title, systemImage: section.icon)
          .badge(section == .trash ? storeManager.deletedObjects.count : 0)
      }
    }
  }
}
