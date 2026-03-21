import FilechuteCore
import SwiftUI

struct DetailView: View {
    let object: StoredObject
    var storeManager: StoreManager
    var onQuickLook: () -> Void
    @State private var objectTags: [Tag] = []
    @State private var newTagName = ""
    @State private var versionHistory: [StoredObject] = []
    @State private var allExistingTags: [Tag] = []
    @State private var suggestedTags: [String] = []
    @State private var renameHistory: [RenameEntry] = []
    @State private var showRenameHistory = false

    var body: some View {
        Form {
            Section("Details") {
                HStack {
                    LabeledContent("Name", value: object.name)
                    if !renameHistory.isEmpty {
                        Button {
                            showRenameHistory.toggle()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Rename history")
                        .popover(isPresented: $showRenameHistory) {
                            RenameHistoryView(entries: renameHistory)
                        }
                    }
                }
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
                    Task { try? await storeManager.openObject(object) }
                }
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityLabel("Open file in default application")

                Button("Quick Look") {
                    onQuickLook()
                }
                .keyboardShortcut(" ", modifiers: [])
                .accessibilityLabel("Preview file with Quick Look")

                Button("Reveal in Finder") {
                    Task { try? await storeManager.openObjectWith(object) }
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
                                Task { try? await storeManager.openObject(version) }
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
        .task(id: "\(object.id)-\(object.name)-\(object.modifiedAt?.timeIntervalSince1970 ?? 0)") {
            await loadTags()
            await loadVersionHistory()
            await loadExistingTags()
            await loadSuggestions()
            await loadRenameHistory()
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
        let ext = await storeManager.fileExtension(for: object)
        let service = TagSuggestionService(database: storeManager.database)
        let suggested = (try? await service.suggestTags(forFilename: object.name, extension: ext)) ?? []
        let appliedNames = Set(objectTags.map { $0.name.lowercased() })
        suggestedTags = suggested.filter { !appliedNames.contains($0.lowercased()) }
    }

    private func loadRenameHistory() async {
        let entries = (try? await storeManager.database.renameHistory(for: object.id)) ?? []
        renameHistory = entries.map { RenameEntry(oldName: $0.oldName, newName: $0.newName, date: $0.date) }
    }
}

struct RenameHistoryView: View {
    let entries: [RenameEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rename History")
                .font(.headline)
            ForEach(entries) { entry in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(entry.oldName)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(entry.newName)
                        }
                        .font(.caption)
                        Text(entry.date, format: .dateTime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 250)
    }
}
