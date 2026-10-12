import AppKit

/// Modal alerts do not always dispatch the SwiftUI menu's editing commands.
final class EditingTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let editor = currentEditor() as? NSTextView,
            let command = EditingShortcut(event)
        else { return super.performKeyEquivalent(with: event) }
        switch command {
        case .cut: editor.cut(nil)
        case .copy: editor.copy(nil)
        case .paste: editor.paste(nil)
        case .selectAll: editor.selectAll(nil)
        case .undo: editor.undoManager?.undo()
        case .redo: editor.undoManager?.redo()
        }
        return true
    }
}

enum EditingShortcut {
    case cut, copy, paste, selectAll, undo, redo
    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard event.type == .keyDown, modifiers == .command || modifiers == [.command, .shift]
        else { return nil }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers.contains(.shift) {
            guard key == "z" else { return nil }
            self = .redo
            return
        }
        switch key {
        case "x": self = .cut
        case "c": self = .copy
        case "v": self = .paste
        case "a": self = .selectAll
        case "z": self = .undo
        default: return nil
        }
    }
}
