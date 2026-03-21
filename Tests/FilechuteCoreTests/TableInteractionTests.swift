import Testing

@testable import FilechuteCore

@Suite("TableInteraction - Return key")
struct ReturnKeyTests {
    @Test("Return starts rename when item selected and not editing")
    func returnStartsRename() {
        let ctx = InteractionContext(hasSelection: true)
        #expect(TableInteraction.reduce(key: .returnKey, context: ctx) == .startRename)
    }

    @Test("Return passes through when already editing")
    func returnPassesThroughWhenEditing() {
        let ctx = InteractionContext(isEditing: true, hasSelection: true)
        #expect(TableInteraction.reduce(key: .returnKey, context: ctx) == .passthrough)
    }

    @Test("Return passes through when text field focused")
    func returnPassesThroughWhenTextFieldFocused() {
        let ctx = InteractionContext(isTextFieldFocused: true, hasSelection: true)
        #expect(TableInteraction.reduce(key: .returnKey, context: ctx) == .passthrough)
    }

    @Test("Return passes through when nothing selected")
    func returnPassesThroughNoSelection() {
        let ctx = InteractionContext()
        #expect(TableInteraction.reduce(key: .returnKey, context: ctx) == .passthrough)
    }

    @Test("Return passes through when editing in text field")
    func returnPassesThroughEditingInTextField() {
        let ctx = InteractionContext(isEditing: true, isTextFieldFocused: true, hasSelection: true)
        #expect(TableInteraction.reduce(key: .returnKey, context: ctx) == .passthrough)
    }
}

@Suite("TableInteraction - Escape key")
struct EscapeKeyTests {
    @Test("Escape cancels rename when editing")
    func escapeCancelsRename() {
        let ctx = InteractionContext(isEditing: true)
        #expect(TableInteraction.reduce(key: .escape, context: ctx) == .cancelRename)
    }

    @Test("Escape passes through when not editing")
    func escapePassesThroughNotEditing() {
        let ctx = InteractionContext()
        #expect(TableInteraction.reduce(key: .escape, context: ctx) == .passthrough)
    }
}

@Suite("TableInteraction - Arrow keys")
struct ArrowKeyTests {
    @Test("Up arrow navigates Quick Look when visible")
    func upArrowNavigatesQL() {
        let ctx = InteractionContext(isQuickLookVisible: true)
        #expect(TableInteraction.reduce(key: .upArrow, context: ctx) == .navigateQuickLook(direction: -1))
    }

    @Test("Down arrow navigates Quick Look when visible")
    func downArrowNavigatesQL() {
        let ctx = InteractionContext(isQuickLookVisible: true)
        #expect(TableInteraction.reduce(key: .downArrow, context: ctx) == .navigateQuickLook(direction: 1))
    }

    @Test("Up arrow passes through when Quick Look not visible")
    func upArrowPassesThroughNoQL() {
        let ctx = InteractionContext()
        #expect(TableInteraction.reduce(key: .upArrow, context: ctx) == .passthrough)
    }

    @Test("Down arrow passes through when Quick Look not visible")
    func downArrowPassesThroughNoQL() {
        let ctx = InteractionContext()
        #expect(TableInteraction.reduce(key: .downArrow, context: ctx) == .passthrough)
    }
}

@Suite("TableInteraction - Space key")
struct SpaceKeyTests {
    @Test("Space toggles Quick Look when item selected")
    func spaceTogglesQL() {
        let ctx = InteractionContext(hasSelection: true)
        #expect(TableInteraction.reduce(key: .space, context: ctx) == .toggleQuickLook)
    }

    @Test("Space passes through when editing")
    func spacePassesThroughWhenEditing() {
        let ctx = InteractionContext(isEditing: true, hasSelection: true)
        #expect(TableInteraction.reduce(key: .space, context: ctx) == .passthrough)
    }

    @Test("Space passes through when nothing selected")
    func spacePassesThroughNoSelection() {
        let ctx = InteractionContext()
        #expect(TableInteraction.reduce(key: .space, context: ctx) == .passthrough)
    }
}

@Suite("TableInteraction - Command+Down")
struct CommandDownTests {
    @Test("Command+Down opens selected items")
    func commandDownOpens() {
        let ctx = InteractionContext(hasSelection: true)
        #expect(TableInteraction.reduce(key: .commandDown, context: ctx) == .openSelected)
    }

    @Test("Command+Down passes through when nothing selected")
    func commandDownPassesThroughNoSelection() {
        let ctx = InteractionContext()
        #expect(TableInteraction.reduce(key: .commandDown, context: ctx) == .passthrough)
    }
}
