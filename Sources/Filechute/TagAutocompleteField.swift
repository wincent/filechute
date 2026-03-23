import FilechuteCore
import SwiftUI

struct TagAutocompleteField: View {
  @Binding var text: String
  let existingTags: [Tag]
  let onSubmit: (String) -> Void

  @State private var showSuggestions = false
  @State private var selectedIndex: Int = -1

  private var suggestions: [Tag] {
    guard !text.isEmpty else { return [] }
    let lower = text.lowercased()
    return existingTags.filter { $0.name.lowercased().hasPrefix(lower) }
  }

  private var visibleSuggestions: ArraySlice<Tag> {
    suggestions.prefix(5)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        TextField("Add tag", text: $text)
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            if selectedIndex >= 0, selectedIndex < visibleSuggestions.count {
              text = visibleSuggestions[visibleSuggestions.startIndex + selectedIndex].name
            }
            submitTag()
          }
          .onChange(of: text) { _, newValue in
            showSuggestions = !newValue.isEmpty
            selectedIndex = -1
          }
          .onKeyPress(keys: [.downArrow, .upArrow]) { keyPress in
            let count = visibleSuggestions.count
            guard showSuggestions, count > 0 else { return .ignored }
            if keyPress.key == .downArrow {
              selectedIndex = min(selectedIndex + 1, count - 1)
            } else {
              selectedIndex = max(selectedIndex - 1, -1)
            }
            return .handled
          }
          .onKeyPress(.escape) {
            guard showSuggestions else { return .ignored }
            showSuggestions = false
            selectedIndex = -1
            return .handled
          }
          .accessibilityLabel("New tag name")
        Button(action: submitTag) {
          Image(systemName: "plus.circle.fill")
        }
        .buttonStyle(.borderless)
        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityLabel("Add tag")
      }

      if showSuggestions && !visibleSuggestions.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(visibleSuggestions.enumerated()), id: \.element.id) { index, tag in
            Button {
              text = tag.name
              submitTag()
            } label: {
              Text(tag.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                  index == selectedIndex
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(.clear)
                )
                .foregroundStyle(index == selectedIndex ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Suggestion: \(tag.name)")
          }
        }
        .padding(4)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
      }
    }
  }

  private func submitTag() {
    let name = text.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    text = ""
    showSuggestions = false
    selectedIndex = -1
    onSubmit(name)
  }
}
