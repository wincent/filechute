import SwiftUI

struct SettingsView: View {
  @State private var patterns: [String] =
    UserDefaults.standard.stringArray(forKey: "ignoredFilePatterns") ?? [".DS_Store"]
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
    Form {
      Section {
        List {
          ForEach(patterns, id: \.self) { pattern in
            HStack {
              Text(pattern)
                .font(.body.monospaced())
              Spacer()
              Button {
                remove(pattern)
              } label: {
                Image(systemName: "minus.circle.fill")
                  .foregroundStyle(.red)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(minHeight: 60)

        HStack {
          TextField("Pattern (e.g. *.tmp)", text: $newPattern)
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .onSubmit { add() }
          Button("Add", action: add)
            .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        if let validationError {
          Text(validationError)
            .foregroundStyle(.red)
            .font(.caption)
        }
      } header: {
        Text("Ignored File Patterns")
      } footer: {
        Text(
          "Files matching these patterns are skipped during directory import."
            + " Use * as a wildcard for zero or more characters."
        )
      }
    }
    .formStyle(.grouped)
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

  private func remove(_ pattern: String) {
    patterns.removeAll { $0 == pattern }
    save()
  }

  private func save() {
    UserDefaults.standard.set(patterns, forKey: "ignoredFilePatterns")
  }
}
