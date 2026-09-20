import Foundation

/// A log that survives the thing it is logging about.
///
/// THE FAILURE THIS EXISTS FOR. On 2026-09-20 Caleb said Plynn keeps breaking.
/// Every measurable thing was healthy: three days of uptime, no crash report,
/// no jetsam, microphone and Accessibility both granted, the Parakeet model
/// present and loaded on the ANE, the main thread idle in a normal event loop,
/// and the hotkey watchdog compiled into the running binary. And there was no
/// way to say what had gone wrong, because this app had 34 `NSLog` calls, no
/// file, and not one line in the unified log across those three days.
///
/// That includes the watchdog's own "hotkey tap was dead, rebuilt". The one
/// component written specifically to recover a known failure could not tell
/// anybody whether it had ever fired.
///
/// An app that breaks intermittently and keeps no record cannot be debugged,
/// only guessed at, and every guess costs the person another day of it
/// breaking. So: a plain file, appended to, rotated, readable with `cat`.
public enum PlynnLog {
    private static let queue = DispatchQueue(label: "co.charmtechnologies.plynn.log")
    private static let maxBytes = 2 * 1024 * 1024

    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Plynn", isDirectory: true)
    }

    public static var fileURL: URL { directory.appendingPathComponent("plynn.log") }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.timeZone = TimeZone.current
        return f
    }()

    /// Write one line. Never throws and never blocks the caller on I/O: a
    /// logger that can break the app it is instrumenting is worse than none.
    public static func write(_ message: String) {
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        // Keep NSLog too. It costs nothing and it is what a `log stream`
        // session shows while somebody is watching live.
        NSLog("%@", message)
        queue.async {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                rotateIfNeeded(fm)
                guard let data = line.data(using: .utf8) else { return }
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: fileURL, options: .atomic)
                }
            } catch {
                // Deliberately silent. There is nowhere left to report to.
            }
        }
    }

    /// One previous file is kept. Two megabytes is roughly a week of normal
    /// use, and the interesting lines are always the recent ones.
    private static func rotateIfNeeded(_ fm: FileManager) {
        guard let size = try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              size > maxBytes else { return }
        let previous = directory.appendingPathComponent("plynn.log.1")
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: fileURL, to: previous)
    }
}

/// Drop-in for the `NSLog` calls that were already here, same signature, so
/// the call sites did not have to be rewritten by hand and cannot drift.
public func plog(_ format: String, _ args: CVarArg...) {
    let message = args.isEmpty ? format : String(format: format, arguments: args)
    PlynnLog.write(message)
}
