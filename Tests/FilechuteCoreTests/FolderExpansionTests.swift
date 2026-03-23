import Testing

@testable import FilechuteCore

private func folder(_ id: Int64, parent: Int64? = nil) -> Folder {
  Folder(id: id, name: "f\(id)", parentId: parent)
}

@Suite("Folder.expandableFolderIds")
struct FolderExpansionTests {
  // Tree:  1 -> 2 -> 4
  //          -> 3
  let tree: [Folder] = [
    folder(1),
    folder(2, parent: 1),
    folder(3, parent: 1),
    folder(4, parent: 2),
  ]

  @Test("Single folder with no children returns only itself")
  func leafFolder() {
    let ids = Folder.expandableFolderIds(under: 3, in: tree)
    #expect(ids == [3])
  }

  @Test("Folder with only leaf children returns only itself")
  func parentOfLeaves() {
    let ids = Folder.expandableFolderIds(under: 2, in: tree)
    #expect(ids == [2])
  }

  @Test("Recursively collects all expandable ancestors")
  func recursiveExpansion() {
    let ids = Folder.expandableFolderIds(under: 1, in: tree)
    // folder 1 has child 2 which has children, so both are included
    // folder 3 is a leaf child of 1, excluded
    // folder 4 is a leaf child of 2, excluded
    #expect(ids == [1, 2])
  }

  @Test("Deep tree collects all intermediate nodes")
  func deepTree() {
    // 10 -> 20 -> 30 -> 40 (leaf)
    let deep: [Folder] = [
      folder(10),
      folder(20, parent: 10),
      folder(30, parent: 20),
      folder(40, parent: 30),
    ]
    let ids = Folder.expandableFolderIds(under: 10, in: deep)
    #expect(ids == [10, 20, 30])
  }

  @Test("Unrelated folders are not included")
  func disjointTrees() {
    let forests: [Folder] = [
      folder(1),
      folder(2, parent: 1),
      folder(3, parent: 2),
      folder(100),
      folder(101, parent: 100),
      folder(102, parent: 101),
    ]
    let ids = Folder.expandableFolderIds(under: 1, in: forests)
    #expect(ids == [1, 2])
  }

  @Test("Empty folder list returns only the target ID")
  func emptyList() {
    let ids = Folder.expandableFolderIds(under: 99, in: [])
    #expect(ids == [99])
  }
}
