import FilechuteCore
import SwiftUI

enum BulkTagEditFocus: Hashable {
  case textField
  case tagList
}

struct BulkTagEditView: View {
  let selectedObjectIds: Set<Int64>
  var storeManager: StoreManager
  let onDismiss: () -> Void

  @State private var newTagName = ""
  @FocusState private var focus: BulkTagEditFocus?
  @State private var focusedTagIndex = 0

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
      .onKeyPress(.tab) {
        if focus == .textField && !tagEntries.isEmpty {
          focus = .tagList
          focusedTagIndex = min(focusedTagIndex, max(tagEntries.count - 1, 0))
          return .handled
        } else if focus == .tagList {
          focus = .textField
          return .handled
        }
        return .ignored
      }
    }
    .onAppear {
      DispatchQueue.main.async {
        focus = .textField
      }
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
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(tagEntries.enumerated()), id: \.element.tag.id) { index, entry in
            tagRow(
              tag: entry.tag,
              state: entry.state,
              isFocused: focus == .tagList && index == focusedTagIndex
            )
            .id(entry.tag.id)
          }
        }
      }
      .frame(maxHeight: 300)
      .focusable()
      .focused($focus, equals: .tagList)
      .focusEffectDisabled()
      .onKeyPress(keys: [.upArrow, .downArrow]) { keyPress in
        let count = tagEntries.count
        guard count > 0 else { return .ignored }
        if keyPress.key == .downArrow {
          focusedTagIndex = min(focusedTagIndex + 1, count - 1)
        } else {
          focusedTagIndex = max(focusedTagIndex - 1, 0)
        }
        proxy.scrollTo(tagEntries[focusedTagIndex].tag.id)
        return .handled
      }
      .onKeyPress(.space) {
        let count = tagEntries.count
        guard focusedTagIndex >= 0, focusedTagIndex < count else { return .ignored }
        let entry = tagEntries[focusedTagIndex]
        Task { await toggleTag(entry.tag, from: entry.state) }
        return .handled
      }
    }
  }

  private func tagRow(tag: Tag, state: TagApplyState, isFocused: Bool) -> some View {
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
      .background(
        isFocused
          ? AnyShapeStyle(Color.accentColor.opacity(0.2))
          : AnyShapeStyle(.clear)
      )
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
      existingTags: storeManager.allTags.map(\.tag),
      focusedField: $focus
    ) { name in
      newTagName = ""
      Task {
        try? await storeManager.addTagToObjects(name, objectIds: selectedObjectIds)
      }
    }
  }
}
