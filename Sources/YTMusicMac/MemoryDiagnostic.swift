import Foundation
import Darwin

/// Resident memory snapshot for the app, plus the WKWebView's WebContent
/// process if we can find it. Surfaced in the status-bar menu so we can
/// SEE growth over a long listening session instead of guessing.
///
/// Note: the WebContent process is a separate child of WebKit's network
/// daemon, not of us directly, so we look it up by its bundle name. If
/// macOS ever moves it under a different name this returns 0 and we just
/// show the app RSS — degrades cleanly.
enum MemoryDiagnostic {
    /// Captured once at first access; used to show "+N MB since launch".
    static let launchRSS: UInt64 = currentRSS()

    /// Resident set size of the current process, in bytes.
    static func currentRSS() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                          task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }

    /// Sum of RSS for all WebContent processes on the system that look like
    /// ours (matching by parent app bundle path / argv). Best-effort.
    static func webContentRSS() -> UInt64 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "rss=,command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return 0 }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return 0 }
        let needle = "com.apple.WebKit.WebContent"
        var total: UInt64 = 0
        for line in out.split(separator: "\n") {
            let s = String(line)
            guard s.contains(needle) else { continue }
            guard s.contains("YTMusic") || s.contains("youtube") else { continue }
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if let kbStr = trimmed.split(separator: " ").first,
               let kb = UInt64(kbStr) {
                total += kb * 1024
            }
        }
        return total
    }

    /// Cached WebContent RSS — refreshed by a background task, NEVER on
    /// the main thread (otherwise menuWillOpen would block while `ps`
    /// scans the whole process table).
    private static var cachedWebContent: UInt64 = 0
    private static var refreshInFlight = false

    /// "App 78 MB (+12 since launch) · WebContent 184 MB"
    /// Returns instantly; the WebContent value is whatever was last
    /// resolved asynchronously. We kick off a fresh background refresh
    /// so the NEXT menu open is up-to-date.
    static func summary() -> String {
        let cur = currentRSS()
        let delta = Int64(cur) - Int64(launchRSS)
        var parts = ["App \(format(cur))"]
        let sign = delta >= 0 ? "+" : "−"
        parts.append("(\(sign)\(format(UInt64(abs(delta)))) since launch)")
        if cachedWebContent > 0 {
            parts.append("· WebContent \(format(cachedWebContent))")
        }
        refreshWebContentInBackground()
        return parts.joined(separator: " ")
    }

    private static func refreshWebContentInBackground() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        DispatchQueue.global(qos: .utility).async {
            let v = webContentRSS()
            DispatchQueue.main.async {
                cachedWebContent = v
                refreshInFlight = false
            }
        }
    }

    private static func format(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        return String(format: "%.0f MB", mb)
    }
}
