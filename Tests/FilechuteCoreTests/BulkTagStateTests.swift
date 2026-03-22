import Testing

@testable import FilechuteCore

@Suite("BulkTagState")
struct BulkTagStateTests {
  @Test("All objects have the tag")
  func allHaveTag() {
    let state = BulkTagState.compute(
      tagName: "photo",
      selectedObjectIds: [1, 2, 3],
      tagNamesByObject: [1: ["photo"], 2: ["photo", "nature"], 3: ["photo"]]
    )
    #expect(state == .all)
  }

  @Test("No objects have the tag")
  func noneHaveTag() {
    let state = BulkTagState.compute(
      tagName: "video",
      selectedObjectIds: [1, 2, 3],
      tagNamesByObject: [1: ["photo"], 2: ["document"], 3: ["photo"]]
    )
    #expect(state == .none)
  }

  @Test("Some objects have the tag")
  func someHaveTag() {
    let state = BulkTagState.compute(
      tagName: "photo",
      selectedObjectIds: [1, 2, 3],
      tagNamesByObject: [1: ["photo"], 2: ["document"], 3: ["photo"]]
    )
    #expect(state == .some)
  }

  @Test("Empty selection returns none")
  func emptySelection() {
    let state = BulkTagState.compute(
      tagName: "photo",
      selectedObjectIds: [],
      tagNamesByObject: [1: ["photo"]]
    )
    #expect(state == .none)
  }

  @Test("Case-insensitive matching")
  func caseInsensitive() {
    let state = BulkTagState.compute(
      tagName: "Photo",
      selectedObjectIds: [1, 2],
      tagNamesByObject: [1: ["photo"], 2: ["PHOTO"]]
    )
    #expect(state == .all)
  }

  @Test("Single object with tag")
  func singleObjectWithTag() {
    let state = BulkTagState.compute(
      tagName: "photo",
      selectedObjectIds: [1],
      tagNamesByObject: [1: ["photo"]]
    )
    #expect(state == .all)
  }

  @Test("Single object without tag")
  func singleObjectWithoutTag() {
    let state = BulkTagState.compute(
      tagName: "video",
      selectedObjectIds: [1],
      tagNamesByObject: [1: ["photo"]]
    )
    #expect(state == .none)
  }

  @Test("Object not in mapping counts as not having tag")
  func objectNotInMapping() {
    let state = BulkTagState.compute(
      tagName: "photo",
      selectedObjectIds: [1, 2],
      tagNamesByObject: [1: ["photo"]]
    )
    #expect(state == .some)
  }
}
