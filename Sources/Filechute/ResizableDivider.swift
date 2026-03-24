import SwiftUI

struct ResizableDivider: View {
  @Binding var height: Double
  let minHeight: Double
  let maxHeight: Double

  @State private var startHeight: Double?

  var body: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor))
      .frame(height: 1)
      .frame(maxWidth: .infinity)
      .overlay {
        Rectangle()
          .fill(Color.clear)
          .frame(height: 8)
          .contentShape(Rectangle())
          .cursor(.resizeUpDown)
          .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
              .onChanged { value in
                if startHeight == nil {
                  startHeight = height
                }
                let newHeight = startHeight! + value.translation.height
                height = min(max(newHeight, minHeight), maxHeight)
              }
              .onEnded { _ in
                startHeight = nil
              }
          )
      }
  }
}

extension View {
  func cursor(_ cursor: NSCursor) -> some View {
    onHover { inside in
      if inside {
        cursor.push()
      } else {
        NSCursor.pop()
      }
    }
  }
}
