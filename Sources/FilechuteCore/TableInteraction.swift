public enum KeyInput: Sendable, Hashable {
    case returnKey
    case escape
    case upArrow
    case downArrow
    case space
    case commandDown
}

public struct InteractionContext: Sendable, Hashable {
    public var isEditing: Bool
    public var isTextFieldFocused: Bool
    public var hasSelection: Bool
    public var isQuickLookVisible: Bool

    public init(
        isEditing: Bool = false,
        isTextFieldFocused: Bool = false,
        hasSelection: Bool = false,
        isQuickLookVisible: Bool = false
    ) {
        self.isEditing = isEditing
        self.isTextFieldFocused = isTextFieldFocused
        self.hasSelection = hasSelection
        self.isQuickLookVisible = isQuickLookVisible
    }
}

public enum InteractionEffect: Sendable, Hashable {
    case startRename
    case cancelRename
    case toggleQuickLook
    case navigateQuickLook(direction: Int)
    case openSelected
    case passthrough
}

public enum TableInteraction {
    public static func reduce(key: KeyInput, context: InteractionContext) -> InteractionEffect {
        switch key {
        case .returnKey:
            if context.isEditing { return .passthrough }
            if context.isTextFieldFocused { return .passthrough }
            if context.hasSelection { return .startRename }
            return .passthrough

        case .escape:
            if context.isEditing { return .cancelRename }
            return .passthrough

        case .upArrow:
            if context.isQuickLookVisible { return .navigateQuickLook(direction: -1) }
            return .passthrough

        case .downArrow:
            if context.isQuickLookVisible { return .navigateQuickLook(direction: 1) }
            return .passthrough

        case .space:
            if context.isEditing { return .passthrough }
            if context.hasSelection { return .toggleQuickLook }
            return .passthrough

        case .commandDown:
            if context.hasSelection { return .openSelected }
            return .passthrough
        }
    }
}
