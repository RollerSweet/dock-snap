import AppKit
import UniformTypeIdentifiers

// The settings UI, hosted inside the menu-bar popover (and a fallback window
// if the menu-bar icon is disabled). All state lives in Settings.shared, so
// multiple instances stay in sync automatically.
final class SettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSettingsChanged: (() -> Void)?
    var onQuit: (() -> Void)?

    private let tabControl = NSSegmentedControl(
        labels: ["Automatic", "Manual"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let container = NSView()
    private var automaticView: NSView!
    private var manualView: NSView!
    private var containerHeight: NSLayoutConstraint!
    private var didFreezeHeight = false

    private var startAtLoginSeg: NSSegmentedControl!
    private var menuBarSeg: NSSegmentedControl!
    private var modifierSeg: NSSegmentedControl!
    private var footerLabel: NSTextField!
    private var tableView: NSTableView!

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Self.popoverWidth, height: 360))
        // Don't let the frame impose a height constraint — the constraint chain
        // alone should drive height, so fittingSize is the true content height.
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: Self.popoverWidth).isActive = true
        buildUI()
        showTab(0)
    }

    private static let popoverWidth: CGFloat = 360

    override func viewWillAppear() {
        super.viewWillAppear()
        // Freeze the popover to the Automatic tab's natural height once metrics
        // are accurate. Both tabs then share this height (the Manual table just
        // scrolls within it), so switching tabs never resizes the popover —
        // sidestepping NSPopover's refusal to shrink.
        if !didFreezeHeight {
            view.layoutSubtreeIfNeeded()
            containerHeight = container.heightAnchor.constraint(equalToConstant: ceil(container.frame.height))
            containerHeight.isActive = true
            didFreezeHeight = true
            view.layoutSubtreeIfNeeded()
        }
        preferredContentSize = NSSize(width: Self.popoverWidth, height: ceil(view.fittingSize.height))
    }

    // MARK: - Layout

    private func buildUI() {
        let content = view

        // Header: logo mark + title.
        let logo = NSImageView()
        logo.image = dockSnapMenuBarImage(pointSize: 15)
        logo.contentTintColor = .labelColor
        logo.imageScaling = .scaleProportionallyDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 15).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 15).isActive = true
        let title = NSTextField(labelWithString: "DockSnap")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let header = NSStackView(views: [logo, title])
        header.orientation = .horizontal
        header.spacing = 6
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)

        tabControl.target = self
        tabControl.action = #selector(tabChanged)
        tabControl.selectedSegment = 0
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabControl)

        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(container)

        // Footer: Quit button.
        let quitButton = NSButton(title: "Quit DockSnap", target: self, action: #selector(quitTapped))
        quitButton.bezelStyle = .rounded
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(quitButton)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(separator)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            header.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            tabControl.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            tabControl.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            tabControl.widthAnchor.constraint(equalToConstant: 200),

            container.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            separator.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            quitButton.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            quitButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            quitButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])

        // Only the active tab lives in the container at any time (pinned on all
        // four edges), so the container hugs it exactly — the inactive tab can
        // never impose a minimum height that blocks the popover from shrinking.
        automaticView = buildAutomaticView()
        manualView = buildManualView()
        automaticView.translatesAutoresizingMaskIntoConstraints = false
        manualView.translatesAutoresizingMaskIntoConstraints = false
        updateFooter()
    }

    private func makeToggleRow(title: String, isOn: Bool, action: Selector) -> (row: NSView, seg: NSSegmentedControl) {
        let seg = NSSegmentedControl(labels: ["ON", "OFF"], trackingMode: .selectOne, target: self, action: action)
        seg.selectedSegment = isOn ? 0 : 1
        seg.translatesAutoresizingMaskIntoConstraints = false
        seg.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)

        let row = NSStackView(views: [seg, label])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return (row, seg)
    }

    private func buildAutomaticView() -> NSView {
        let wrapper = NSView()

        let loginRow = makeToggleRow(title: "Start at login", isOn: Settings.shared.startAtLogin, action: #selector(startAtLoginChanged(_:)))
        let menuRow = makeToggleRow(title: "Menu bar icon", isOn: Settings.shared.showMenuBarIcon, action: #selector(menuBarChanged(_:)))
        startAtLoginSeg = loginRow.seg
        menuBarSeg = menuRow.seg

        let header = NSTextField(labelWithString: "LAUNCH DOCK APPS WITH:")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor

        modifierSeg = NSSegmentedControl(
            labels: ModifierKey.allCases.map { "\($0.symbol) \($0.title)" },
            trackingMode: .selectAny,  // allow a combination, e.g. ⌘ + ⌥
            target: self,
            action: #selector(modifierChanged)
        )
        syncModifierSegSelection()
        modifierSeg.translatesAutoresizingMaskIntoConstraints = false

        footerLabel = NSTextField(wrappingLabelWithString: "")
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [loginRow.row, menuRow.row, header, modifierSeg, footerLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(22, after: menuRow.row)
        stack.setCustomSpacing(16, after: modifierSeg)

        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -4),
            modifierSeg.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footerLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return wrapper
    }

    private func buildManualView() -> NSView {
        let wrapper = NSView()

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 52
        table.style = .plain
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = []
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        tableView = table
        scroll.documentView = table

        let addButton = NSButton(title: "+", target: self, action: #selector(addApp))
        let removeButton = NSButton(title: "−", target: self, action: #selector(removeApp))
        for button in [addButton, removeButton] {
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        }
        let buttonRow = NSStackView(views: [addButton, removeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        wrapper.addSubview(scroll)
        wrapper.addSubview(buttonRow)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: wrapper.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),

            buttonRow.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            buttonRow.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    // MARK: - Tabs

    @objc private func tabChanged() { showTab(tabControl.selectedSegment) }

    private func showTab(_ index: Int) {
        let active: NSView = index == 0 ? automaticView : manualView
        guard active.superview !== container else { return }

        container.subviews.forEach { $0.removeFromSuperview() }
        container.addSubview(active)
        NSLayoutConstraint.activate([
            active.topAnchor.constraint(equalTo: container.topAnchor),
            active.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            active.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            active.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        if index == 1 { tableView.reloadData() }
    }

    private func updateFooter() {
        let s = Settings.shared.automaticModifierSymbols
        footerLabel?.stringValue =
            "\(s)1 opens the first Dock app, \(s)2 the second, … through \(s)9.  \(s)` opens Finder."
    }

    // MARK: - Automatic actions

    @objc private func startAtLoginChanged(_ sender: NSSegmentedControl) {
        Settings.shared.startAtLogin = (sender.selectedSegment == 0)
        Settings.shared.save()
        onSettingsChanged?()
    }

    @objc private func menuBarChanged(_ sender: NSSegmentedControl) {
        Settings.shared.showMenuBarIcon = (sender.selectedSegment == 0)
        Settings.shared.save()
        onSettingsChanged?()
    }

    @objc private func modifierChanged() {
        var selected = Set<ModifierKey>()
        for (i, mod) in ModifierKey.allCases.enumerated() where modifierSeg.isSelected(forSegment: i) {
            selected.insert(mod)
        }
        // At least one modifier is required — an empty combo would make bare
        // number keys launch Dock apps. Reject the deselection and restore.
        guard !selected.isEmpty else {
            NSSound.beep()
            syncModifierSegSelection()
            return
        }
        Settings.shared.automaticModifiers = selected
        Settings.shared.save()
        updateFooter()
    }

    // Reflect the persisted combo onto the segmented control's highlights.
    private func syncModifierSegSelection() {
        for (i, mod) in ModifierKey.allCases.enumerated() {
            modifierSeg.setSelected(Settings.shared.automaticModifiers.contains(mod), forSegment: i)
        }
    }

    @objc private func quitTapped() { onQuit?() }

    // MARK: - Manual actions

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Settings.shared.manualEntries.append(ManualEntry(appPath: url.path, shortcut: nil))
            Settings.shared.save()
            self.tableView.reloadData()
            let row = Settings.shared.manualEntries.count - 1
            self.tableView.scrollRowToVisible(row)
            if let cell = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ManualRowView {
                self.view.window?.makeFirstResponder(cell.recorder)
            }
        }

        if let window = view.window { panel.beginSheetModal(for: window, completionHandler: handle) }
        else { handle(panel.runModal()) }
    }

    @objc private func removeApp() {
        let row = tableView.selectedRow
        guard row >= 0, row < Settings.shared.manualEntries.count else { return }
        Settings.shared.manualEntries.remove(at: row)
        Settings.shared.save()
        tableView.reloadData()
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        Settings.shared.manualEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("ManualRow")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? ManualRowView) ?? {
            let cell = ManualRowView()
            cell.identifier = id
            return cell
        }()

        cell.configure(entry: Settings.shared.manualEntries[row])
        cell.onChange = { shortcut in
            guard row < Settings.shared.manualEntries.count else { return }
            Settings.shared.manualEntries[row].shortcut = shortcut
            Settings.shared.save()
        }
        cell.onClear = { [weak self] in
            guard let self, row < Settings.shared.manualEntries.count else { return }
            Settings.shared.manualEntries[row].shortcut = nil
            Settings.shared.save()
            self.tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        }
        return cell
    }
}

// MARK: - Menu-bar / header logo mark (template image)

// A simple monochrome mark derived from the app logo: a keycap with ⌥.
// isTemplate=true lets macOS tint it for light/dark menu bars.
func dockSnapMenuBarImage(pointSize: CGFloat = 18) -> NSImage {
    let size = NSSize(width: pointSize, height: pointSize)
    let image = NSImage(size: size, flipped: false) { rect in
        let inset = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.10)
        let path = NSBezierPath(roundedRect: inset, xRadius: inset.width * 0.26, yRadius: inset.width * 0.26)
        path.lineWidth = max(1, rect.width * 0.085)
        NSColor.black.setStroke()
        path.stroke()

        let glyph = "\u{2325}" as NSString  // ⌥
        let font = NSFont.systemFont(ofSize: rect.width * 0.52, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let glyphSize = glyph.size(withAttributes: attrs)
        glyph.draw(
            at: NSPoint(x: rect.midX - glyphSize.width / 2, y: rect.midY - glyphSize.height / 2),
            withAttributes: attrs
        )
        return true
    }
    image.isTemplate = true
    return image
}
