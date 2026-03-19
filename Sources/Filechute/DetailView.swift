import FilechuteCore
import QuickLookUI
import SwiftUI

struct DetailView: View {
    let object: StoredObject
    var storeManager: StoreManager
    @State private var objectTags: [Tag] = []
    @State private var newTagName = ""
    @State private var versionHistory: [StoredObject] = []
    @State private var allExistingTags: [Tag] = []
    @State private var suggestedTags: [String] = []
    @State private var previewURL: URL?
    @State private var showPreview = false

    var body: some View {
        Form {
            Section("Details") {
                LabeledContent("Name", value: object.name)
                LabeledContent("Hash") {
                    Text(object.hash.hexString)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Added") {
                    Text(object.createdAt, format: .dateTime)
                }
            }

            Section("Actions") {
                Button("Open") {
                    try? storeManager.openObject(object)
                }
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityLabel("Open file in default application")

                Button("Quick Look") {
                    showQuickLook()
                }
                .keyboardShortcut(" ", modifiers: [])
                .accessibilityLabel("Preview file with Quick Look")

                Button("Reveal in Finder") {
                    try? storeManager.openObjectWith(object)
                }
                .accessibilityLabel("Show file in Finder")
            }

            Section("Tags") {
                ForEach(objectTags) { tag in
                    HStack {
                        Text(tag.name)
                        Spacer()
                        Button {
                            Task {
                                try? await storeManager.removeTag(tag.id, from: object.id)
                                await loadTags()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag.name)")
                    }
                }

                if !suggestedTags.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggestions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ForEach(suggestedTags, id: \.self) { suggestion in
                                Button(suggestion) {
                                    Task {
                                        try? await storeManager.addTag(suggestion, to: object.id)
                                        await loadTags()
                                        await loadSuggestions()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Add suggested tag \(suggestion)")
                            }
                        }
                    }
                }

                TagAutocompleteField(
                    text: $newTagName,
                    existingTags: allExistingTags
                ) { name in
                    Task {
                        try? await storeManager.addTag(name, to: object.id)
                        await loadTags()
                        await loadSuggestions()
                    }
                }
            }

            if !versionHistory.isEmpty {
                Section("Version History") {
                    ForEach(versionHistory) { version in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(version.name)
                                    .font(.caption)
                                Text(version.createdAt, format: .dateTime)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open") {
                                try? storeManager.openObject(version)
                            }
                            .font(.caption)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Version from \(version.createdAt.formatted())")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: object.id) {
            await loadTags()
            await loadVersionHistory()
            await loadExistingTags()
            await loadSuggestions()
        }
    }

    private func showQuickLook() {
        let ext = object.name.components(separatedBy: ".").count > 1
            ? object.name.components(separatedBy: ".").last
            : nil
        if let url = try? storeManager.fileAccessService.openTemporaryCopy(
            hash: object.hash,
            name: object.name,
            extension: ext
        ) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func loadTags() async {
        objectTags = (try? await storeManager.tags(for: object.id)) ?? []
    }

    private func loadVersionHistory() async {
        versionHistory = (try? await storeManager.versionHistory(for: object.id)) ?? []
    }

    private func loadExistingTags() async {
        allExistingTags = (try? await storeManager.database.allTags()) ?? []
    }

    private func loadSuggestions() async {
        let ext = object.name.components(separatedBy: ".").count > 1
            ? object.name.components(separatedBy: ".").last
            : nil
        let service = TagSuggestionService(database: storeManager.database)
        let suggested = (try? await service.suggestTags(forFilename: object.name, extension: ext)) ?? []
        let appliedNames = Set(objectTags.map { $0.name.lowercased() })
        suggestedTags = suggested.filter { !appliedNames.contains($0.lowercased()) }
    }
}
