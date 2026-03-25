import Foundation
import Testing

@testable import FilechuteCore

@Suite("TextExtractorService")
struct TextExtractorServiceTests {
  @Test("Extract text from plain text file")
  func extractPlainText() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("filechute-text-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("sample.txt")
    try "Hello world, this is a test document.".write(to: file, atomically: true, encoding: .utf8)

    let text = TextExtractorService.extractText(from: file)
    #expect(text != nil)
    #expect(text?.contains("test document") == true)
  }

  @Test("Returns nil for unsupported file types")
  func unsupportedType() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("filechute-text-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("image.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)

    let text = TextExtractorService.extractText(from: file)
    #expect(text == nil)
  }

  @Test("Truncate preserves valid UTF-8")
  func truncateUTF8() {
    let text = String(repeating: "a", count: 200)
    let truncated = TextExtractorService.truncate(text, toUTF8Bytes: 100)
    #expect(truncated.utf8.count == 100)
  }

  @Test("Truncate handles multi-byte characters at boundary")
  func truncateMultibyte() {
    let text = String(repeating: "\u{00E9}", count: 100)  // e-acute, 2 bytes each
    let truncated = TextExtractorService.truncate(text, toUTF8Bytes: 101)
    #expect(truncated.utf8.count == 100)  // 50 characters * 2 bytes
    #expect(String(truncated) != nil)
  }

  @Test("Truncate returns short strings unchanged")
  func truncateShort() {
    let text = "short"
    let result = TextExtractorService.truncate(text, toUTF8Bytes: 1000)
    #expect(result == text)
  }

  @Test("Extract text from markdown file")
  func extractMarkdown() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("filechute-text-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("readme.md")
    try "# Title\n\nSome markdown content.".write(to: file, atomically: true, encoding: .utf8)

    let text = TextExtractorService.extractText(from: file)
    #expect(text != nil)
    #expect(text?.contains("markdown content") == true)
  }
}
