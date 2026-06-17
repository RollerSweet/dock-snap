import AppKit
import CoreGraphics

// Virtual keycodes for 1-9 (number row above the letters)
let numberKeyCodes: [CGKeyCode] = [
    18,  // 1
    19,  // 2
    20,  // 3
    21,  // 4
    23,  // 5
    22,  // 6
    26,  // 7
    28,  // 8
    25,  // 9
]
let graveKeyCode: CGKeyCode = 50  // backtick / grave (key left of 1)

private var globalEventTap: CFMachPort?

final class HotkeyEngine {
    static let shared = HotkeyEngine()
    private init() {}

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var refreshTimer: DispatchSourceTimer?
    private var trustTimer: DispatchSourceTimer?

    // Dock app list is cached and refreshed OFF the event-tap thread, so the
    // keyboard hook never blocks on the `defaults export` subprocess.
    private let cacheLock = NSLock()
    private var cachedApps: [String] = []
    private let refreshQueue = DispatchQueue(label: "com.tamirmadar.docksnap.dockrefresh", qos: .utility)

    func dockApps() -> [String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedApps
    }

    private func setDockApps(_ apps: [String]) {
        cacheLock.lock()
        cachedApps = apps
        cacheLock.unlock()
    }

    func start() {
        // Prime the cache once at startup (not on the tap thread), then keep it
        // fresh in the background.
        setDockApps(getDockApps())
        let timer = DispatchSource.makeTimerSource(queue: refreshQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.setDockApps(getDockApps())
        }
        timer.resume()
        refreshTimer = timer

        // Self-healing: poll Accessibility trust on the main thread and create
        // or destroy the tap to match. Revoking permission instantly removes
        // our tap (keyboard returns to normal); granting it starts the tap
        // without needing an app relaunch.
        let trust = DispatchSource.makeTimerSource(queue: .main)
        trust.schedule(deadline: .now(), repeating: 1.5)
        trust.setEventHandler { [weak self] in self?.syncTapWithTrust() }
        trust.resume()
        trustTimer = trust
    }

    private func syncTapWithTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted, tap == nil {
            createTap()
        } else if !trusted, tap != nil {
            destroyTap()
            log("Accessibility permission lost — event tap removed (keyboard unaffected).")
        }
    }

    private func createTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyCallback,
            userInfo: nil
        ) else {
            log("Could not create event tap (Accessibility not yet granted).")
            return
        }

        tap = eventTap
        globalEventTap = eventTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        log("Event tap created successfully. Running!")
    }

    private func destroyTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        globalEventTap = nil
    }

    // Cleanly tear everything down. Called on quit; macOS also removes the tap
    // automatically when the process exits, so the keyboard is never left in a
    // modified state once DockSnap is gone.
    func stop() {
        refreshTimer?.cancel()
        refreshTimer = nil
        trustTimer?.cancel()
        trustTimer = nil
        destroyTap()
        log("Event tap stopped.")
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable the tap if macOS disables it (timeout / heavy input).
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        log("Event tap was disabled, re-enabling...")
        if let tap = globalEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    // When DockSnap itself is frontmost (e.g. recording a shortcut) let keys
    // through so they reach our own UI.
    if NSApp?.isActive == true {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let mods = modifierSet(from: event.flags)
    // Holding a combo emits repeated keyDowns. We still consume those repeats
    // (so no Option-characters leak into the focused app), but only act on the
    // initial press — otherwise a held key would launch/activate over and over.
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let settings = Settings.shared

    // 1) Manual per-app shortcuts take precedence.
    for entry in settings.manualEntries {
        if let shortcut = entry.shortcut, shortcut.keyCode == keyCode, shortcut.modifiers == mods {
            if !isRepeat {
                let path = entry.appPath
                log("Manual shortcut \(shortcut.displayString) -> \(entry.appName)")
                DispatchQueue.main.async { launchApp(atPath: path) }
            }
            return nil
        }
    }

    // 2) Automatic: exactly the configured modifier combo + a number / backtick.
    if mods == settings.automaticModifiers {
        if keyCode == UInt16(graveKeyCode) {
            if !isRepeat {
                log("\(settings.automaticModifierSymbols)` pressed — opening Finder")
                DispatchQueue.main.async {
                    launchApp(atPath: "/System/Library/CoreServices/Finder.app")
                }
            }
            return nil
        }
        if let index = numberKeyCodes.firstIndex(of: CGKeyCode(keyCode)) {
            if !isRepeat {
                log("\(settings.automaticModifierSymbols)\(index + 1) pressed")
                let apps = HotkeyEngine.shared.dockApps()  // cached; never blocks
                DispatchQueue.main.async { activateApp(at: index, apps: apps) }
            }
            return nil
        }
    }

    // Everything else passes through untouched.
    return Unmanaged.passUnretained(event)
}
