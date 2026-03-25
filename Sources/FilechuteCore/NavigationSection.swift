public enum NavigationSection: Hashable {
  case store
  case allItems
  case folder(Int64)
  case trash

  public var folderId: Int64? {
    if case .folder(let id) = self { return id }
    return nil
  }
}
