import Foundation
import Testing

@testable import FilechuteCore

@Suite("NavigationHistory")
struct NavigationHistoryTests {
  @Test("Initial state")
  func initialState() {
    let history = NavigationHistory()
    #expect(!history.canGoBack)
    #expect(!history.canGoForward)
    #expect(history.current == NavigationState())
  }

  @Test("Push creates forward entry")
  func pushCreatesEntry() {
    var history = NavigationHistory()
    let state = NavigationState(sidebarSelection: .folder(1))
    history.push(state)

    #expect(history.current == state)
    #expect(history.canGoBack)
    #expect(!history.canGoForward)
  }

  @Test("Go back returns previous state")
  func goBack() {
    var history = NavigationHistory(coalesceInterval: 0)
    let initial = history.current
    history.push(NavigationState(sidebarSelection: .folder(1)))

    let restored = history.goBack()
    #expect(restored == initial)
    #expect(!history.canGoBack)
    #expect(history.canGoForward)
  }

  @Test("Go forward returns next state")
  func goForward() {
    var history = NavigationHistory(coalesceInterval: 0)
    let folderState = NavigationState(sidebarSelection: .folder(1))
    history.push(folderState)
    _ = history.goBack()

    let restored = history.goForward()
    #expect(restored == folderState)
    #expect(history.canGoBack)
    #expect(!history.canGoForward)
  }

  @Test("Push after back discards forward entries")
  func pushAfterBackDiscardsForward() {
    var history = NavigationHistory(coalesceInterval: 0)
    history.push(NavigationState(sidebarSelection: .folder(1)))
    history.push(NavigationState(sidebarSelection: .folder(2)))
    _ = history.goBack()

    history.push(NavigationState(sidebarSelection: .folder(3)))
    #expect(!history.canGoForward)
    #expect(history.current.sidebarSelection == .folder(3))
  }

  @Test("Go back at start returns nil")
  func goBackAtStart() {
    var history = NavigationHistory()
    #expect(history.goBack() == nil)
  }

  @Test("Go forward at end returns nil")
  func goForwardAtEnd() {
    var history = NavigationHistory()
    #expect(history.goForward() == nil)
  }

  @Test("Push identical state is no-op")
  func pushIdenticalState() {
    var history = NavigationHistory()
    let initial = history.current
    history.push(initial)

    #expect(!history.canGoBack)
    #expect(history.current == initial)
  }

  @Test("Column selections are preserved in state")
  func columnSelections() {
    var history = NavigationHistory(coalesceInterval: 0)
    let state = NavigationState(
      sidebarSelection: .folder(1),
      columnSelections: [[5, 6], [7]]
    )
    history.push(state)
    history.push(NavigationState(sidebarSelection: .allItems))
    let restored = history.goBack()

    #expect(restored?.columnSelections == [[5, 6], [7]])
  }

  @Test("Multiple back/forward traversals")
  func multipleTraversals() {
    var history = NavigationHistory(coalesceInterval: 0)
    let s1 = NavigationState(sidebarSelection: .folder(1))
    let s2 = NavigationState(sidebarSelection: .folder(2))
    let s3 = NavigationState(sidebarSelection: .folder(3))
    history.push(s1)
    history.push(s2)
    history.push(s3)

    #expect(history.goBack() == s2)
    #expect(history.goBack() == s1)
    #expect(history.goForward() == s2)
    #expect(history.goForward() == s3)
    #expect(!history.canGoForward)
  }

  @Test("Coalescing replaces top entry for rapid pushes")
  func coalescing() {
    var history = NavigationHistory(coalesceInterval: 10)
    history.push(NavigationState(sidebarSelection: .folder(1)))
    history.push(NavigationState(sidebarSelection: .folder(2)))
    history.push(NavigationState(sidebarSelection: .folder(3)))

    #expect(history.current.sidebarSelection == .folder(3))
    let prev = history.goBack()
    #expect(prev?.sidebarSelection == .allItems)
    #expect(!history.canGoBack)
  }

  @Test("Coalescing resets after back/forward")
  func coalesceResetsAfterNavigation() {
    var history = NavigationHistory(coalesceInterval: 10)
    history.push(NavigationState(sidebarSelection: .folder(1)))
    _ = history.goBack()
    history.push(NavigationState(sidebarSelection: .folder(2)))

    #expect(history.current.sidebarSelection == .folder(2))
    let prev = history.goBack()
    #expect(prev?.sidebarSelection == .allItems)
  }

  @Test("Trash navigation is tracked")
  func trashNavigation() {
    var history = NavigationHistory(coalesceInterval: 0)
    history.push(NavigationState(sidebarSelection: .trash))

    #expect(history.current.sidebarSelection == .trash)
    let prev = history.goBack()
    #expect(prev?.sidebarSelection == .allItems)
  }
}
