import FilechuteCore
import SwiftUI

struct BulkTagEditView: View {
  let selectedObjectIds: Set<Int64>
  var storeManager: StoreManager
  let onDismiss: () -> Void

  @State private var newTagName = ""

  private var tagEntries: [(tag: Tag, state: TagApplyState)] {
    guard !selectedObjectIds.isEmpty else { return [] }
    return storeManager.allTags.map { tc in
      let state = BulkTagState.compute(
        tagName: tc.tag.name,
        selectedObjectIds: selectedObjectIds,
        tagNamesByObject: storeManager.tagNamesByObject
      )
      return (tc.tag, state)
    }
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.3)
        .ignoresSafeArea()
        .onTapGesture { onDismiss() }

      VStack(spacing: 0) {
        header
        Divider()

        if selectedObjectIds.isEmpty {
          emptyState
        } else {
          if !tagEntries.isEmpty {
            tagList
            Divider()
          }
          addTagField
            .padding()
        }
      }
      .background(.background)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .shadow(radius: 20)
      .frame(width: 360)
    }
  }

  private var header: some View {
    HStack {
      Text("Edit Tags")
        .font(.headline)
      Spacer()
      if !selectedObjectIds.isEmpty {
        let count = selectedObjectIds.count
        Text("\(count) \(count == 1 ? "item" : "items")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
    }
    .padding()
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "tag")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("No items selected")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  private var tagList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(tagEntries, id: \.tag.id) { entry in
          tagRow(tag: entry.tag, state: entry.state)
        }
      }
    }
    .frame(maxHeight: 300)
  }

  private func tagRow(tag: Tag, state: TagApplyState) -> some View {
    Button {
      Task { await toggleTag(tag, from: state) }
    } label: {
      HStack(spacing: 8) {
        checkboxIcon(for: state)
          .frame(width: 16)
        Text(tag.name)
        Spacer()
      }
      .contentShape(Rectangle())
      .padding(.horizontal)
      .padding(.vertical, 6)
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func checkboxIcon(for state: TagApplyState) -> some View {
    switch state {
    case .all:
      Image(systemName: "checkmark.square.fill")
        .foregroundStyle(Color.accentColor)
    case .some:
      Image(systemName: "minus.square.fill")
        .foregroundStyle(Color.accentColor)
    case .none:
      Image(systemName: "square")
        .foregroundStyle(.secondary)
    }
  }

  private func toggleTag(_ tag: Tag, from state: TagApplyState) async {
    switch state {
    case .none, .some:
      try? await storeManager.addTagToObjects(tag.name, objectIds: selectedObjectIds)
    case .all:
      try? await storeManager.removeTagFromObjects(tag.id, objectIds: selectedObjectIds)
    }
  }

  private var addTagField: some View {
    TagAutocompleteField(
      text: $newTagName,
      existingTags: storeManager.allTags.map(\.tag)
    ) { name in
      newTagName = ""
      Task {
        try? await storeManager.addTagToObjects(name, objectIds: selectedObjectIds)
      }
    }
  }
}
