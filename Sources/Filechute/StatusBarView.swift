import FilechuteCore
import SwiftUI

struct StatusBarView: View {
  var objects: [StoredObject]
  var selection: Set<Int64>
  var sizesByObject: [Int64: UInt64]
  var isGridMode: Bool
  @Binding var thumbnailSize: Double

  var body: some View {
    HStack(spacing: 12) {
      if isGridMode {
        Color.clear.frame(width: sliderWidth, height: 0)
      }

      Spacer()

      Text(summaryText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("status-bar-summary")

      Spacer()

      if isGridMode {
        Slider(value: $thumbnailSize, in: 64...1280)
          .frame(width: sliderWidth)
          .controlSize(.mini)
          .accessibilityIdentifier("thumbnail-size-slider")
          .accessibilityLabel("Thumbnail size")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(.bar)
    .accessibilityIdentifier("status-bar")
  }

  private let sliderWidth: CGFloat = 100

  private var summaryText: String {
    if selection.isEmpty {
      let total = totalSize(for: objects.map(\.id))
      return "\(objects.count) items (\(formatBytes(total)))"
    } else {
      let total = totalSize(for: Array(selection))
      return "\(selection.count) of \(objects.count) selected (\(formatBytes(total)))"
    }
  }

  private func totalSize(for ids: [Int64]) -> UInt64 {
    ids.reduce(UInt64(0)) { sum, id in sum + (sizesByObject[id] ?? 0) }
  }

  private func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
}
