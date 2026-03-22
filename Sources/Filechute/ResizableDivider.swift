import SwiftUI

struct ResizableDivider: View {
  @Binding var height: Double
  let minHeight: Double
  let maxHeight: Double

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
            DragGesture(minimumDistance: 1)
              .onChanged { value in
                let newHeight = height + value.translation.height
                height = min(max(newHeight, minHeight), maxHeight)
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
