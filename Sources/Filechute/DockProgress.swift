import AppKit
import FilechuteCore
import Observation

@MainActor
final class DockProgress {
  private let progress: IngestionProgress
  private let imageView = NSImageView()
  private var isShowing = false

  init(progress: IngestionProgress) {
    self.progress = progress
    startObserving()
  }

  private func startObserving() {
    withObservationTracking {
      _ = progress.isActive
      _ = progress.processedFiles
    } onChange: {
      Task { @MainActor [weak self] in
        self?.update()
        self?.startObserving()
      }
    }
  }

  private func update() {
    if progress.isActive {
      show(fraction: progress.fractionCompleted)
    } else if isShowing {
      hide()
    }
  }

  private func show(fraction: Double) {
    guard let appIcon = NSApplication.shared.applicationIconImage else { return }

    let size = appIcon.size
    let image = NSImage(size: size)
    image.lockFocus()

    appIcon.draw(
      in: NSRect(origin: .zero, size: size),
      from: .zero,
      operation: .sourceOver,
      fraction: 1.0
    )

    let barHeight: CGFloat = 12
    let barInset: CGFloat = 8
    let barY: CGFloat = 8
    let barRect = NSRect(
      x: barInset,
      y: barY,
      width: size.width - barInset * 2,
      height: barHeight
    )

    NSColor.black.withAlphaComponent(0.6).setFill()
    NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

    let fillWidth = max(barHeight, barRect.width * fraction)
    let fillRect = NSRect(
      x: barRect.origin.x,
      y: barRect.origin.y,
      width: fillWidth,
      height: barHeight
    )
    NSColor.white.setFill()
    NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

    image.unlockFocus()

    imageView.image = image
    NSApp.dockTile.contentView = imageView
    NSApp.dockTile.display()
    isShowing = true
  }

  private func hide() {
    NSApp.dockTile.contentView = nil
    NSApp.dockTile.display()
    isShowing = false
  }
}
