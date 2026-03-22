import Foundation
import UniformTypeIdentifiers

public struct TagSuggestionService: Sendable {
  public let database: Database

  public init(database: Database) {
    self.database = database
  }

  public func suggestTags(
    forFilename filename: String,
    extension ext: String?
  ) async throws -> [String] {
    var suggestions: [String] = []

    if let ext, !ext.isEmpty {
      let utType = UTType(filenameExtension: ext)
      let normalized = utType?.preferredFilenameExtension ?? ext
      suggestions.append(normalized.lowercased())
    }

    let nameWithoutExt: String
    if let ext, !ext.isEmpty, filename.hasSuffix(".\(ext)") {
      nameWithoutExt = String(filename.dropLast(ext.count + 1))
    } else {
      nameWithoutExt = filename
    }

    let tokens = tokenize(nameWithoutExt)

    for token in tokens {
      if isYearLike(token) {
        suggestions.append(token)
      }
    }

    let existingTags = try await database.allTags()
    let existingNames = Set(existingTags.map { $0.name.lowercased() })

    for token in tokens {
      let lower = token.lowercased()
      if existingNames.contains(lower) && !suggestions.contains(where: { $0.lowercased() == lower })
      {
        suggestions.append(lower)
      }
    }

    let mimeCategory = mimeCategory(forExtension: ext)
    if let category = mimeCategory {
      suggestions.append(category)
    }

    return suggestions.uniqued()
  }

  private func tokenize(_ name: String) -> [String] {
    let separators = CharacterSet.alphanumerics.inverted
    return
      name
      .components(separatedBy: separators)
      .filter { !$0.isEmpty && $0.count > 1 }
  }

  private func isYearLike(_ token: String) -> Bool {
    guard token.count == 4, let year = Int(token) else { return false }
    return year >= 1900 && year <= 2100
  }

  private func mimeCategory(forExtension ext: String?) -> String? {
    guard let ext, let utType = UTType(filenameExtension: ext) else { return nil }
    if utType.conforms(to: .image) { return "image" }
    if utType.conforms(to: .pdf) || utType.conforms(to: .text) || utType.conforms(to: .presentation)
    {
      return "document"
    }
    if utType.conforms(to: .spreadsheet) { return "spreadsheet" }
    if utType.conforms(to: .audio) { return "audio" }
    if utType.conforms(to: .movie) || utType.conforms(to: .video) { return "video" }
    if utType.conforms(to: .archive) { return "archive" }
    return nil
  }
}

extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
