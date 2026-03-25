import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

public struct TextExtractorService: Sendable {
  private static let maxTextBytes = 100_000

  public static func extractText(from url: URL) -> String? {
    guard let utType = UTType(filenameExtension: url.pathExtension) else {
      return nil
    }

    let text: String?
    if utType.conforms(to: .pdf) {
      text = extractPDFText(from: url)
    } else if utType.conforms(to: .plainText) {
      text = extractPlainText(from: url)
    } else if utType.conforms(to: .rtf) || utType.conforms(to: .rtfd) {
      text = extractAttributedStringText(from: url)
    } else if utType.identifier == "org.openxmlformats.wordprocessingml.document" {
      text = extractAttributedStringText(from: url)
    } else {
      return nil
    }

    guard let text, !text.isEmpty else { return nil }
    return truncate(text, toUTF8Bytes: maxTextBytes)
  }

  private static func extractPDFText(from url: URL) -> String? {
    guard let document = PDFDocument(url: url) else { return nil }
    var pages: [String] = []
    for i in 0..<document.pageCount {
      if let page = document.page(at: i), let text = page.string {
        pages.append(text)
      }
    }
    let result = pages.joined(separator: "\n")
    return result.isEmpty ? nil : result
  }

  static func truncate(_ text: String, toUTF8Bytes maxBytes: Int) -> String {
    guard text.utf8.count > maxBytes else { return text }
    let utf8 = text.utf8
    var end = utf8.index(utf8.startIndex, offsetBy: maxBytes)
    while end > utf8.startIndex, String(utf8[utf8.startIndex..<end]) == nil {
      utf8.formIndex(before: &end)
    }
    return String(utf8[utf8.startIndex..<end]) ?? ""
  }

  private static func extractPlainText(from url: URL) -> String? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    let limited = data.prefix(maxTextBytes)
    return String(data: limited, encoding: .utf8)
  }

  private static func extractAttributedStringText(from url: URL) -> String? {
    guard
      let attributed = try? NSAttributedString(
        url: url, options: [:], documentAttributes: nil
      )
    else { return nil }
    let text = attributed.string
    return text.isEmpty ? nil : text
  }
}
