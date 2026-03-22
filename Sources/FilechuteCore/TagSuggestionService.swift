import Foundation

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
      suggestions.append(ext.lowercased())
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
    guard let ext = ext?.lowercased() else { return nil }
    let imageExts: Set = [
      "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "svg",
    ]
    let docExts: Set = ["pdf", "doc", "docx", "txt", "rtf", "odt", "pages"]
    let spreadsheetExts: Set = ["xls", "xlsx", "csv", "numbers", "ods"]
    let audioExts: Set = ["mp3", "wav", "aac", "flac", "m4a", "ogg", "wma"]
    let videoExts: Set = ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm"]
    let archiveExts: Set = ["zip", "tar", "gz", "bz2", "7z", "rar", "dmg"]

    if imageExts.contains(ext) { return "image" }
    if docExts.contains(ext) { return "document" }
    if spreadsheetExts.contains(ext) { return "spreadsheet" }
    if audioExts.contains(ext) { return "audio" }
    if videoExts.contains(ext) { return "video" }
    if archiveExts.contains(ext) { return "archive" }
    return nil
  }
}

extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
