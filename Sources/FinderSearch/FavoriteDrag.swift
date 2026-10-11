import AppKit
import SwiftUI

/// Observe row drags without taking clicks or context menus away from the list.
struct FavoriteDragTarget: NSViewRepresentable {
    let path: String
    let move: (String, String) -> Void
    func makeNSView(context: Context) -> FavoriteDragView { FavoriteDragView() }
    func updateNSView(_ view: FavoriteDragView, context: Context) {
        view.path = path
        view.move = move
    }
}

final class FavoriteDragView: NSView {
    private static let rows = NSHashTable<FavoriteDragView>.weakObjects()
    var path = ""
    var move: (String, String) -> Void = { _, _ in }
    private var monitor: Any?
    private var start: CGPoint?
    private var dragging = false
    private(set) var dragPreview: NSView?
    private(set) var insertionMarker: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        Self.rows.add(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
        ) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }

    @discardableResult func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else {
            if event.type == .leftMouseUp { reset() }
            return false
        }
        if event.type == .keyDown, event.keyCode == 53, dragging {
            reset()
            return true
        }
        switch event.type {
        case .leftMouseDown:
            reset()
            guard window.attachedSheet == nil, NSApp.modalWindow == nil,
                event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                bounds.contains(convert(event.locationInWindow, from: nil))
            else { return false }
            start = event.locationInWindow
        case .leftMouseDragged:
            guard let start else { return false }
            if !dragging,
                hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 6
            {
                dragging = true
                NSCursor.closedHand.push()
            }
            if dragging { updatePreview(at: event.locationInWindow) }
            return dragging
        case .leftMouseUp:
            let wasDragging = dragging
            let target = targetRow(at: event.locationInWindow)?.path
            reset()
            if wasDragging, let target, target != path { move(path, target) }
            return wasDragging
        default: break
        }
        return false
    }

    private func targetRow(at point: CGPoint) -> FavoriteDragView? {
        Self.rows.allObjects.first {
            $0.window === window
                && $0.bounds.insetBy(dx: 0, dy: -7)
                    .contains($0.convert(point, from: nil))
        }
    }

    private func updatePreview(at point: CGPoint) {
        guard let host = window?.contentView, let start else { return }
        if dragPreview == nil {
            let preview = FavoriteRowPreview(path: path)
            preview.frame = host.convert(bounds, from: self).insetBy(dx: -6, dy: -6)
            host.addSubview(preview)
            dragPreview = preview
        }
        let origin = host.convert(bounds, from: self).insetBy(dx: -6, dy: -6).origin
        let current = host.convert(point, from: nil), initial = host.convert(start, from: nil)
        dragPreview?.setFrameOrigin(
            CGPoint(
                x: origin.x + current.x - initial.x, y: origin.y + current.y - initial.y))
        guard let target = targetRow(at: point), target !== self else {
            insertionMarker?.isHidden = true
            return
        }
        if insertionMarker == nil {
            let marker = FavoriteInsertionMarker()
            host.addSubview(marker)
            insertionMarker = marker
        }
        let targetRect = target.convert(target.bounds, to: nil)
        let sourceRect = convert(bounds, to: nil)
        let edge = targetRect.midY < sourceRect.midY ? targetRect.minY - 7 : targetRect.maxY + 7
        let edgePoint = host.convert(CGPoint(x: targetRect.minX, y: edge), from: nil)
        insertionMarker?.frame = NSRect(
            x: edgePoint.x, y: edgePoint.y - 2, width: targetRect.width, height: 4)
        insertionMarker?.isHidden = false
    }

    private func reset() {
        dragPreview?.removeFromSuperview(); dragPreview = nil
        insertionMarker?.removeFromSuperview(); insertionMarker = nil
        if dragging { NSCursor.pop() }
        dragging = false
        start = nil
    }
    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        reset()
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if dragging { NSCursor.pop() }
        dragPreview?.removeFromSuperview()
        insertionMarker?.removeFromSuperview()
    }
}

private final class FavoriteRowPreview: NSView {
    private let label: (name: String, symbol: String)
    init(path: String) {
        label = FavoriteFolders.label(for: path)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 5
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let icon = NSImage(systemSymbolName: label.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.controlAccentColor]))
        icon?.draw(in: NSRect(x: 6, y: (bounds.height - 16) / 2, width: 16, height: 16))
        (label.name as NSString).draw(
            with: NSRect(x: 28, y: (bounds.height - 17) / 2, width: bounds.width - 34, height: 17),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.controlTextColor,
            ])
    }
}

private final class FavoriteInsertionMarker: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: 1, width: bounds.width, height: 2),
            xRadius: 1, yRadius: 1
        ).fill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
    }
}
