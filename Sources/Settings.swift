import AppKit
import CoreGraphics

// MARK: - Modifier keys

enum ModifierKey: String, Codable, CaseIterable, Hashable {
    case shift, control, option, command

    var cgFlag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .command: return .maskCommand
        }
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .control: return "⌃"
        case .option: return "⌥"
        case .command: return "⌘"
        }
    }

    var title: String { rawValue.capitalized }
}

func modifierSet(from flags: CGEventFlags) -> Set<ModifierKey> {
    var set = Set<ModifierKey>()
    if flags.contains(.maskShift) { set.insert(.shift) }
    if flags.contains(.maskControl) { set.insert(.control) }
    if flags.contains(.maskAlternate) { set.insert(.option) }
    if flags.contains(.maskCommand) { set.insert(.command) }
    return set
}

func modifierSet(from flags: NSEvent.ModifierFlags) -> Set<ModifierKey> {
    var set = Set<ModifierKey>()
    if flags.contains(.shift) { set.insert(.shift) }
    if flags.contains(.control) { set.insert(.control) }
    if flags.contains(.option) { set.insert(.option) }
    if flags.contains(.command) { set.insert(.command) }
    return set
}

// Modifier symbols in the conventional macOS order (⌃⌥⇧⌘), e.g. {.command,
// .option} -> "⌥⌘". Shared by manual-shortcut display and the automatic combo.
func modifierSymbols(_ mods: Set<ModifierKey>) -> String {
    let order: [ModifierKey] = [.control, .option, .shift, .command]
    return order.filter { mods.contains($0) }.map(\.symbol).joined()
}

// MARK: - Shortcuts

struct ManualShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: Set<ModifierKey>

    var displayString: String {
        modifierSymbols(modifiers) + KeyCodeMap.label(for: keyCode)
    }
}

struct ManualEntry: Codable, Equatable {
    var appPath: String
    var shortcut: ManualShortcut?
    var appName: String { DockSnap.appName(from: appPath) }
}

// Disambiguate the free `appName(from:)` helper inside ManualEntry.
private enum DockSnap {
    static func appName(from path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}

// MARK: - Settings store

final class Settings {
    static let shared = Settings()

    private let defaultsKey = "DockSnapSettings"

    // The automatic launcher fires when EXACTLY this set of modifiers is held
    // together with a number / backtick (e.g. {.command, .option} -> ⌘⌥1).
    // Always non-empty: an empty set would hijack the bare number keys.
    var automaticModifiers: Set<ModifierKey> = [.option]
    var startAtLogin: Bool = false
    var showMenuBarIcon: Bool = true
    var manualEntries: [ManualEntry] = []

    var hasSaved: Bool { UserDefaults.standard.data(forKey: defaultsKey) != nil }

    // Combined symbol string for the configured combo, e.g. "⌥⌘".
    var automaticModifierSymbols: String { modifierSymbols(automaticModifiers) }

    private struct Payload: Codable {
        var automaticModifier: ModifierKey?         // legacy single value — read for migration
        var automaticModifiers: Set<ModifierKey>?   // current multi-modifier combo
        var startAtLogin: Bool
        var showMenuBarIcon: Bool
        var manualEntries: [ManualEntry]
    }

    private init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        // Prefer the new field; migrate the old single value; else keep default.
        if let mods = payload.automaticModifiers, !mods.isEmpty {
            automaticModifiers = mods
        } else if let legacy = payload.automaticModifier {
            automaticModifiers = [legacy]
        }
        startAtLogin = payload.startAtLogin
        showMenuBarIcon = payload.showMenuBarIcon
        manualEntries = payload.manualEntries
    }

    func save() {
        let payload = Payload(
            automaticModifier: nil,
            automaticModifiers: automaticModifiers,
            startAtLogin: startAtLogin,
            showMenuBarIcon: showMenuBarIcon,
            manualEntries: manualEntries
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
