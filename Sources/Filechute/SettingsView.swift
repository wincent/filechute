import FilechuteCore
import SwiftUI

struct SettingsView: View {
  @State private var patterns: [String] =
    AppDefaults.shared.stringArray(forKey: "ignoredFilePatterns") ?? [".DS_Store"]
  @State private var selection: String?
  @State private var newPattern = ""
  @State private var validationError: String?

  var body: some View {
    TabView {
      Tab("Import", systemImage: "square.and.arrow.down") {
        importSettings
      }
    }
    .frame(width: 450, height: 300)
  }

  private var importSettings: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Ignored File Patterns")
        .font(.headline)

      List(patterns, id: \.self, selection: $selection) { pattern in
        Text(pattern)
          .font(.body.monospaced())
      }
      .listStyle(.bordered(alternatesRowBackgrounds: true))

      HStack(spacing: 4) {
        TextField("Pattern (e.g. *.tmp)", text: $newPattern)
          .textFieldStyle(.roundedBorder)
          .font(.body.monospaced())
          .onSubmit { add() }

        Button(action: add) {
          Image(systemName: "plus").frame(width: 16, height: 16)
        }
        .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)

        Button(action: removeSelected) {
          Image(systemName: "minus").frame(width: 16, height: 16)
        }
        .disabled(selection == nil)
      }

      if let validationError {
        Text(validationError)
          .foregroundStyle(.red)
          .font(.caption)
      }

      Text(
        "Files matching these patterns are skipped during directory import."
          + " Use * as a wildcard for zero or more characters."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding()
  }

  private func add() {
    let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    if trimmed.contains("/") || trimmed.contains(":") {
      validationError = "Patterns cannot contain / or : characters."
      return
    }
    if patterns.contains(trimmed) {
      validationError = "This pattern already exists."
      return
    }
    validationError = nil
    patterns.append(trimmed)
    newPattern = ""
    save()
  }

  private func removeSelected() {
    guard let selection else { return }
    patterns.removeAll { $0 == selection }
    self.selection = nil
    save()
  }

  private func save() {
    AppDefaults.shared.set(patterns, forKey: "ignoredFilePatterns")
  }
}
