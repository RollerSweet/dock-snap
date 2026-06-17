import AppKit
import Foundation

// MARK: - Dock Reader

func getDockApps() -> [String] {
    // Use `defaults export` — reads from cfprefsd (live preferences),
    // not the plist file on disk which is stale until the Dock flushes.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["export", "com.apple.dock", "-"]
    let pipe = Pipe()
    process.standardOutput = pipe

    do {
        try process.run()
    } catch {
        log("WARNING: Failed to launch `defaults`: \(error.localizedDescription)")
        return []
    }

    // Drain the pipe to EOF BEFORE waiting on the process. `defaults export`
    // of a large Dock can exceed the ~64KB pipe buffer; calling waitUntilExit()
    // first would deadlock — the child blocks writing while we block waiting.
    // Reading to EOF lets the child write everything and exit.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let persistentApps = plist["persistent-apps"] as? [[String: Any]] else {
        log("WARNING: Failed to read dock preferences")
        return []
    }
    return extractAppPaths(from: persistentApps)
}

func extractAppPaths(from persistentApps: [[String: Any]]) -> [String] {
    return persistentApps.compactMap { app -> String? in
        guard let tileData = app["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let cfUrl = fileData["_CFURLString"] as? String else {
            return nil
        }
        return appPath(fromCFURLString: cfUrl)
    }
}

// The Dock stores `_CFURLString` as a percent-encoded file URL, e.g.
// "file:///Applications/Google%20Chrome.app/". Decode it to a POSIX path,
// tolerating the rare cases where it is already a plain path, or an unencoded
// "file://" URL that `URL(string:)` rejects (which previously fell through and
// returned an unusable "file://…" string as if it were a path).
func appPath(fromCFURLString cfUrl: String) -> String {
    if let url = URL(string: cfUrl), url.isFileURL {
        return url.path
    }
    if cfUrl.hasPrefix("file://") {
        let body = String(cfUrl.dropFirst("file://".count))
        let decoded = body.removingPercentEncoding ?? body
        // Strip a trailing slash so it matches the url.path form above.
        return decoded.count > 1 && decoded.hasSuffix("/") ? String(decoded.dropLast()) : decoded
    }
    return cfUrl  // already a POSIX path
}

func appName(from path: String) -> String {
    return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
}

// MARK: - App Launcher

func launchApp(atPath appPath: String) {
    let name = appName(from: appPath)
    // Standardize both sides so the comparison is robust to trailing slashes
    // and "."/".." segments. Bundle-path match is reliable; localizedName is a
    // secondary heuristic for the rare app whose bundle moved out from under us.
    let target = URL(fileURLWithPath: appPath).standardizedFileURL.path
    let running = NSWorkspace.shared.runningApplications.first {
        $0.bundleURL?.standardizedFileURL.path == target || $0.localizedName == name
    }

    if let app = running {
        app.activate()
        log("Activated: \(name)")
    } else {
        let url = URL(fileURLWithPath: appPath)
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error = error {
                log("Failed to launch \(name): \(error.localizedDescription)")
            } else {
                log("Launched: \(name)")
            }
        }
    }
}

func activateApp(at index: Int, apps: [String]) {
    guard index < apps.count else {
        log("No app at Dock position \(index + 1)")
        return
    }
    launchApp(atPath: apps[index])
}
