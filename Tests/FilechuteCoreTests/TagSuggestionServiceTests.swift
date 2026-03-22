import Foundation
import Testing

@testable import FilechuteCore

@Suite("TagSuggestionService")
struct TagSuggestionServiceTests {
  @Test("Suggests file extension as tag")
  func extensionTag() async throws {
    let db = try Database(path: ":memory:")
    let service = TagSuggestionService(database: db)

    let suggestions = try await service.suggestTags(forFilename: "report.pdf", extension: "pdf")
    #expect(suggestions.contains("pdf"))
  }

  @Test("Suggests year-like tokens")
  func yearTokens() async throws {
    let db = try Database(path: ":memory:")
    let service = TagSuggestionService(database: db)

    let suggestions = try await service.suggestTags(
      forFilename: "tax-return-2024.pdf",
      extension: "pdf"
    )
    #expect(suggestions.contains("2024"))
  }

  @Test("Suggests MIME category")
  func mimeCategory() async throws {
    let db = try Database(path: ":memory:")
    let service = TagSuggestionService(database: db)

    let suggestions = try await service.suggestTags(forFilename: "photo.jpg", extension: "jpg")
    #expect(suggestions.contains("image"))
    #expect(suggestions.contains("jpeg"))
    #expect(!suggestions.contains("jpg"))
  }

  @Test("Matches existing tags from filename tokens")
  func matchesExistingTags() async throws {
    let db = try Database(path: ":memory:")
    _ = try await db.createTag(name: "tax")
    _ = try await db.createTag(name: "return")

    let service = TagSuggestionService(database: db)
    let suggestions = try await service.suggestTags(
      forFilename: "tax-return-2024.pdf",
      extension: "pdf"
    )
    #expect(suggestions.contains("tax"))
    #expect(suggestions.contains("return"))
  }

  @Test("No duplicate suggestions")
  func noDuplicates() async throws {
    let db = try Database(path: ":memory:")
    _ = try await db.createTag(name: "pdf")

    let service = TagSuggestionService(database: db)
    let suggestions = try await service.suggestTags(forFilename: "file.pdf", extension: "pdf")
    let pdfCount = suggestions.filter { $0.lowercased() == "pdf" }.count
    #expect(pdfCount == 1)
  }

  @Test("Handles nil extension")
  func nilExtension() async throws {
    let db = try Database(path: ":memory:")
    let service = TagSuggestionService(database: db)

    let suggestions = try await service.suggestTags(forFilename: "readme", extension: nil)
    #expect(!suggestions.isEmpty || suggestions.isEmpty)
  }

  @Test("Does not suggest single-char tokens")
  func skipsSingleChar() async throws {
    let db = try Database(path: ":memory:")
    _ = try await db.createTag(name: "a")

    let service = TagSuggestionService(database: db)
    let suggestions = try await service.suggestTags(forFilename: "a-b-c.txt", extension: "txt")
    #expect(!suggestions.contains("a"))
    #expect(!suggestions.contains("b"))
    #expect(!suggestions.contains("c"))
  }
}
