import Foundation
import Combine

final class Log: ObservableObject {
    static let shared = Log()

    struct Entry: Identifiable {
        enum Level: String, CaseIterable {
            case debug, info, warning, error

            var symbol: String {
                switch self {
                case .debug: "ladybug"
                case .info: "info.circle"
                case .warning: "exclamationmark.triangle"
                case .error: "xmark.octagon"
                }
            }
        }

        let id = UUID()
        let date: Date
        let level: Level
        let category: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    let sessionStart = Date()
    private let maxEntries = 800
    private let lock = NSLock()

    private init() {
        installUncaughtExceptionHandler()
        add(.info, "app", "Session started — \(AppInfo.versionString), iOS \(DeviceInfo.systemVersion) on \(DeviceInfo.model)")
    }

    func add(_ level: Entry.Level, _ category: String, _ message: String) {
        let entry = Entry(date: Date(), level: level, category: category, message: message)
        if Thread.isMainThread {
            append(entry)
        } else {
            DispatchQueue.main.async { [weak self] in self?.append(entry) }
        }
    }

    private func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
        add(.info, "app", "Log cleared by user")
    }

    func text(limit: Int = 400) -> String {
        let slice = entries.suffix(limit)
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return slice.map { e in
            "[\(f.string(from: e.date))] \(e.level.rawValue.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0)) \(e.category) — \(e.message)"
        }.joined(separator: "\n")
    }

    private func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "unknown"
            let stack = exception.callStackSymbols.prefix(12).joined(separator: "\n")
            Log.shared.add(.error, "crash", "Uncaught \(exception.name.rawValue): \(reason)\n\(stack)")
        }
    }
}

extension Log {
    static func debug(_ category: String, _ message: String) { shared.add(.debug, category, message) }
    static func info(_ category: String, _ message: String) { shared.add(.info, category, message) }
    static func warn(_ category: String, _ message: String) { shared.add(.warning, category, message) }
    static func error(_ category: String, _ message: String) { shared.add(.error, category, message) }
}
