import AppKit

// One row in the Manual tab: app icon, name, a shortcut recorder, and a clear button.
final class ManualRowView: NSView {
    let icon = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    let recorder = ShortcutRecorderField()
    let clearButton = NSButton()

    var onChange: ((ManualShortcut?) -> Void)?
    var onClear: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        for view in [icon, nameLabel, recorder, clearButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")
        clearButton.isBordered = false
        clearButton.bezelStyle = .inline
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearTapped)

        recorder.onCapture = { [weak self] shortcut in self?.onChange?(shortcut) }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),

            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: recorder.leadingAnchor, constant: -8),

            recorder.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            recorder.centerYAnchor.constraint(equalTo: centerYAnchor),
            recorder.widthAnchor.constraint(equalToConstant: 150),
            recorder.heightAnchor.constraint(equalToConstant: 30),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            clearButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func clearTapped() { onClear?() }

    func configure(entry: ManualEntry) {
        icon.image = NSWorkspace.shared.icon(forFile: entry.appPath)
        nameLabel.stringValue = entry.appName
        recorder.shortcut = entry.shortcut
    }
}
