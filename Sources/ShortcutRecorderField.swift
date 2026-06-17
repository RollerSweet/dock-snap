import AppKit

// A small rounded field that records the next modifier+key combination.
final class ShortcutRecorderField: NSView {
    var onCapture: ((ManualShortcut?) -> Void)?

    var shortcut: ManualShortcut? {
        didSet { needsDisplay = true }
    }

    private var recording = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        recording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Escape cancels recording without changing anything.
        if event.keyCode == 53 {
            recording = false
            window?.makeFirstResponder(nil)
            return
        }

        let mods = modifierSet(from: event.modifierFlags.intersection([.shift, .control, .option, .command]))
        guard !mods.isEmpty else {
            NSSound.beep()  // require at least one modifier
            return
        }

        let captured = ManualShortcut(keyCode: event.keyCode, modifiers: mods)
        shortcut = captured
        recording = false
        window?.makeFirstResponder(nil)
        onCapture?(captured)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)

        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text: String
        let isPlaceholder: Bool
        if recording {
            text = "Type shortcut…"
            isPlaceholder = true
        } else if let shortcut {
            text = shortcut.displayString
            isPlaceholder = false
        } else {
            text = "Click to set"
            isPlaceholder = true
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isPlaceholder ? NSColor.tertiaryLabelColor : NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let textRect = NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
