import Foundation

public struct NavigationState: Equatable {
  public var sidebarSelection: NavigationSection?
  public var columnSelections: [Set<Int64>]

  public init(
    sidebarSelection: NavigationSection? = .allItems,
    columnSelections: [Set<Int64>] = []
  ) {
    self.sidebarSelection = sidebarSelection
    self.columnSelections = columnSelections
  }
}

public struct NavigationHistory {
  private var entries: [NavigationState]
  private var cursor: Int
  private var lastPushTime: Date?
  private let coalesceInterval: TimeInterval

  public var canGoBack: Bool { cursor > 0 }
  public var canGoForward: Bool { cursor < entries.count - 1 }

  public var current: NavigationState { entries[cursor] }

  public init(
    initial: NavigationState = NavigationState(),
    coalesceInterval: TimeInterval = 0.3
  ) {
    entries = [initial]
    cursor = 0
    self.coalesceInterval = coalesceInterval
  }

  public mutating func push(_ state: NavigationState) {
    guard state != current else { return }

    let now = Date()
    let shouldCoalesce: Bool
    if let lastPush = lastPushTime {
      shouldCoalesce = now.timeIntervalSince(lastPush) < coalesceInterval
    } else {
      shouldCoalesce = false
    }

    if shouldCoalesce {
      entries[cursor] = state
    } else {
      entries.removeSubrange((cursor + 1)...)
      entries.append(state)
      cursor = entries.count - 1
    }
    lastPushTime = now
  }

  public mutating func goBack() -> NavigationState? {
    guard canGoBack else { return nil }
    cursor -= 1
    lastPushTime = nil
    return entries[cursor]
  }

  public mutating func goForward() -> NavigationState? {
    guard canGoForward else { return nil }
    cursor += 1
    lastPushTime = nil
    return entries[cursor]
  }
}
