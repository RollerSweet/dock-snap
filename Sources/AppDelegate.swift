import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var fallbackWindow: NSWindow?

    private lazy var settingsVC: SettingsViewController = {
        let vc = SettingsViewController()
        vc.onSettingsChanged = { [weak self] in
            self?.updateMenuBarIcon()
            self?.applyLoginItem()
        }
        vc.onQuit = { NSApp.terminate(nil) }
        return vc
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("DockSnap starting...")
        NSApp.setActivationPolicy(.accessory)  // menu-bar app, no Dock tile

        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )

        popover.behavior = .transient
        popover.contentViewController = settingsVC

        updateMenuBarIcon()
        applyLoginItem()
        HotkeyEngine.shared.start()

        let apps = HotkeyEngine.shared.dockApps()
        log("Dock mapping:")
        for (i, app) in apps.prefix(9).enumerated() {
            log("  \(Settings.shared.automaticModifierSymbols)\(i + 1) -> \(appName(from: app))")
        }

        if !Settings.shared.hasSaved {
            showSettings()          // discoverable on first run
            Settings.shared.save()  // ...but auto-open only once, not every launch
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyEngine.shared.stop()
    }

    // MARK: - Menu bar

    func updateMenuBarIcon() {
        if Settings.shared.showMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = dockSnapMenuBarImage()
            item.button?.target = self
            item.button?.action = #selector(togglePopover)
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Login item

    func applyLoginItem() {
        do {
            if Settings.shared.startAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log("Login item update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Showing settings

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showSettings()
        }
    }

    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let button = statusItem?.button {
            // Make sure the popover owns the settings VC (the fallback window
            // may have borrowed it).
            if popover.contentViewController !== settingsVC {
                popover.contentViewController = settingsVC
            }
            fallbackWindow?.orderOut(nil)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        } else {
            // No menu-bar icon — fall back to a regular window.
            if fallbackWindow == nil {
                let window = NSWindow(
                    contentViewController: settingsVC,
                    style: [.titled, .closable]
                )
                window.title = "DockSnap"
                window.isReleasedWhenClosed = false
                fallbackWindow = window
            } else {
                fallbackWindow?.contentViewController = settingsVC
            }
            fallbackWindow?.center()
            fallbackWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
}

private extension NSWindow {
    convenience init(contentViewController: NSViewController, style: NSWindow.StyleMask) {
        self.init(
            contentRect: contentViewController.view.bounds,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
    }
}
