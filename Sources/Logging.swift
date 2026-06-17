import Foundation

// Output goes to stdout (visible via Console / `log stream` when launched as a
// bundle). A single shared formatter avoids reallocating one per call, and the
// lock serializes writes so lines from the background Dock-refresh queue and
// the main thread never interleave. We flush immediately for live tailing.
private let logLock = NSLock()
private let logFormatter = ISO8601DateFormatter()

func log(_ message: String) {
    logLock.lock()
    defer { logLock.unlock() }
    let ts = logFormatter.string(from: Date())
    print("[\(ts)] \(message)")
    fflush(stdout)
}
