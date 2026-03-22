import AppKit
import FilechuteCore
import SwiftUI

struct PreviewGridView: View {
  var storeManager: StoreManager
  var objects: [StoredObject]
  @Binding var selection: Set<Int64>
  @Binding var columnCount: Int
  var thumbnailSize: Double
  var onOpen: (StoredObject) -> Void
  var onQuickLook: (StoredObject) -> Void
  @State private var anchorId: Int64?
  @FocusState private var isFocused: Bool

  private var cellWidth: CGFloat { thumbnailSize + 16 }

  private var columns: [GridItem] {
    [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth + 60), spacing: 16)]
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollViewReader { proxy in
        ScrollView {
          LazyVGrid(columns: columns, spacing: 16) {
            ForEach(objects) { object in
              PreviewGridCell(
                object: object,
                thumbnailURL: storeManager.thumbnailURL(for: object),
                isSelected: selection.contains(object.id),
                size: thumbnailSize
              )
              .id(object.id)
              .gesture(
                TapGesture(count: 2).onEnded {
                  onOpen(object)
                }
              )
              .simultaneousGesture(
                TapGesture().onEnded {
                  handleClick(object: object)
                  isFocused = true
                }
              )
              .contextMenu {
                Button("Open") { onOpen(object) }
                Button("Quick Look") { onQuickLook(object) }
                Divider()
                Button("Delete", role: .destructive) {
                  Task { try? await storeManager.deleteObject(object.id) }
                }
              }
            }
          }
          .padding()
        }
        .onChange(of: anchorId) { _, newId in
          if let newId {
            withAnimation {
              proxy.scrollTo(newId)
            }
          }
        }
      }
      .onChange(of: geometry.size.width, initial: true) { _, width in
        updateColumnCount(for: width)
      }
      .onChange(of: thumbnailSize) { _, _ in
        updateColumnCount(for: geometry.size.width)
      }
    }
    .focusable()
    .focusEffectDisabled()
    .focused($isFocused)
    .onKeyPress(keys: [.leftArrow], phases: .down) { press in
      navigate(by: -1, extending: press.modifiers.contains(.shift))
    }
    .onKeyPress(keys: [.rightArrow], phases: .down) { press in
      navigate(by: 1, extending: press.modifiers.contains(.shift))
    }
    .onKeyPress(keys: [.upArrow], phases: .down) { press in
      navigate(by: -columnCount, extending: press.modifiers.contains(.shift))
    }
    .onKeyPress(keys: [.downArrow], phases: .down) { press in
      navigate(by: columnCount, extending: press.modifiers.contains(.shift))
    }
    .onKeyPress(.space) {
      guard let id = selection.first,
        let obj = objects.first(where: { $0.id == id })
      else { return .ignored }
      onQuickLook(obj)
      return .handled
    }
    .onKeyPress(characters: .init(charactersIn: "a"), phases: .down) { press in
      guard press.modifiers.contains(.command) else { return .ignored }
      selection = Set(objects.map(\.id))
      return .handled
    }
  }

  private func updateColumnCount(for width: CGFloat) {
    let usable = width - 32
    columnCount = max(1, Int((usable + 16) / (cellWidth + 16)))
  }

  private func handleClick(object: StoredObject) {
    let modifiers = NSEvent.modifierFlags
    if modifiers.contains(.command) {
      if selection.contains(object.id) {
        selection.remove(object.id)
      } else {
        selection.insert(object.id)
      }
      anchorId = object.id
    } else if modifiers.contains(.shift), let lastId = anchorId,
      let lastIndex = objects.firstIndex(where: { $0.id == lastId }),
      let clickedIndex = objects.firstIndex(where: { $0.id == object.id })
    {
      let range = min(lastIndex, clickedIndex)...max(lastIndex, clickedIndex)
      selection = Set(objects[range].map(\.id))
    } else {
      selection = [object.id]
      anchorId = object.id
    }
  }

  private func navigate(by offset: Int, extending: Bool) -> KeyPress.Result {
    guard !objects.isEmpty else { return .ignored }

    let currentIndex: Int
    if let id = anchorId, let idx = objects.firstIndex(where: { $0.id == id }) {
      currentIndex = idx
    } else if let id = selection.first, let idx = objects.firstIndex(where: { $0.id == id }) {
      currentIndex = idx
    } else {
      selection = [objects[0].id]
      anchorId = objects[0].id
      return .handled
    }

    let newIndex = min(max(currentIndex + offset, 0), objects.count - 1)
    let target = objects[newIndex]

    if extending {
      selection.insert(target.id)
    } else {
      selection = [target.id]
    }
    anchorId = target.id
    return .handled
  }
}

struct PreviewGridCell: View {
  let object: StoredObject
  let thumbnailURL: URL
  let isSelected: Bool
  var size: Double = 128

  var body: some View {
    VStack(spacing: 6) {
      thumbnailView
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

      Text(object.name)
        .font(.caption)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(width: size)
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
    )
  }

  @ViewBuilder
  private var thumbnailView: some View {
    if let image = ThumbnailCache.shared.image(for: object.hash, at: thumbnailURL) {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fit)
    } else {
      Image(systemName: iconName)
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.controlBackgroundColor))
    }
  }

  private var iconName: String {
    switch object.fileExtension.lowercased() {
    case "pdf": "doc.richtext"
    case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp", "svg": "photo"
    case "mp4", "mov", "avi", "mkv", "m4v": "film"
    case "mp3", "wav", "aac", "flac", "m4a", "ogg": "music.note"
    case "zip", "tar", "gz", "rar", "7z": "archivebox"
    case "txt", "md", "rtf": "doc.text"
    case "swift", "js", "ts", "py", "rb", "go", "rs", "c", "cpp", "h", "java":
      "chevron.left.forwardslash.chevron.right"
    default: "doc"
    }
  }
}
