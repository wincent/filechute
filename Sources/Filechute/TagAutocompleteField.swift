import FilechuteCore
import SwiftUI

struct TagAutocompleteField: View {
    @Binding var text: String
    let existingTags: [Tag]
    let onSubmit: (String) -> Void

    @State private var showSuggestions = false

    private var suggestions: [Tag] {
        guard !text.isEmpty else { return [] }
        let lower = text.lowercased()
        return existingTags.filter { $0.name.lowercased().hasPrefix(lower) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Add tag", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitTag()
                    }
                    .onChange(of: text) { _, newValue in
                        showSuggestions = !newValue.isEmpty
                    }
                    .accessibilityLabel("New tag name")
                Button(action: submitTag) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add tag")
            }

            if showSuggestions && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(suggestions.prefix(5)) { tag in
                        Button {
                            text = tag.name
                            submitTag()
                        } label: {
                            Text(tag.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Suggestion: \(tag.name)")
                    }
                }
                .padding(4)
                .background(.bar)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func submitTag() {
        let name = text.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        text = ""
        showSuggestions = false
        onSubmit(name)
    }
}
