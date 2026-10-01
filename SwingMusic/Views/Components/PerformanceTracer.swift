import Foundation
import os

final class PerformanceTracer: @unchecked Sendable {
    static let shared = PerformanceTracer()

    nonisolated(unsafe) static var isEnabled = false

    enum Section: Int, CaseIterable {
        case lyricsRender
        case revealMask
        case glyphDraw
        case textBuild
        case background
        case nowPlayingInfo
        case widgetWrite

        var title: String {
            switch self {
            case .lyricsRender: "Draw line"
            case .revealMask: "Reveal mask"
            case .glyphDraw: "Glyphs"
            case .textBuild: "Build text"
            case .background: "Background"
            case .nowPlayingInfo: "Medienplayer"
            case .widgetWrite: "Widget schreiben"
            }
        }
    }

    struct Row: Identifiable {
        let section: Section
        let callsPerSecond: Double
        let millisecondsPerSecond: Double
        let worstMilliseconds: Double

        var id: Int { section.rawValue }
    }

    private let log = OSLog(
        subsystem: "com.swingmusic.app",
        category: .pointsOfInterest
    )
    private var lock = os_unfair_lock_s()
    private var totals = [Double](repeating: 0, count: Section.allCases.count)
    private var counts = [Int](repeating: 0, count: Section.allCases.count)
    private var worst = [Double](repeating: 0, count: Section.allCases.count)
    private var windowStart = CFAbsoluteTimeGetCurrent()

    private var lagWorst: Double = 0
    private var lagSum: Double = 0
    private var lagCount = 0

    private init() {}

    func recordLyricLag(_ lag: Double) {
        guard Self.isEnabled else { return }
        os_unfair_lock_lock(&lock)
        lagWorst = max(lagWorst, lag)
        lagSum += lag
        lagCount += 1
        os_unfair_lock_unlock(&lock)
    }

    func drainLyricLag() -> (worst: Double, average: Double, count: Int) {
        os_unfair_lock_lock(&lock)
        let result = (
            lagWorst * 1000,
            lagCount > 0 ? lagSum / Double(lagCount) * 1000 : 0,
            lagCount
        )
        lagWorst = 0
        lagSum = 0
        lagCount = 0
        os_unfair_lock_unlock(&lock)
        return result
    }

    @inline(__always)
    func measure<T>(_ section: Section, _ body: () throws -> T) rethrows -> T {
        guard Self.isEnabled else { return try body() }
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "section", signpostID: signpostID)
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            os_signpost(.end, log: log, name: "section", signpostID: signpostID)
            record(section, elapsed)
        }
        return try body()
    }

    private func record(_ section: Section, _ elapsed: Double) {
        os_unfair_lock_lock(&lock)
        let index = section.rawValue
        totals[index] += elapsed
        counts[index] += 1
        worst[index] = max(worst[index], elapsed)
        os_unfair_lock_unlock(&lock)
    }

    func drain() -> [Row] {
        os_unfair_lock_lock(&lock)
        let now = CFAbsoluteTimeGetCurrent()
        let window = max(now - windowStart, 0.001)
        let totalsCopy = totals
        let countsCopy = counts
        let worstCopy = worst
        totals = [Double](repeating: 0, count: totals.count)
        counts = [Int](repeating: 0, count: counts.count)
        worst = [Double](repeating: 0, count: worst.count)
        windowStart = now
        os_unfair_lock_unlock(&lock)

        return Section.allCases.compactMap { section in
            let index = section.rawValue
            guard countsCopy[index] > 0 else { return nil }
            return Row(
                section: section,
                callsPerSecond: Double(countsCopy[index]) / window,
                millisecondsPerSecond: totalsCopy[index] / window * 1000,
                worstMilliseconds: worstCopy[index] * 1000
            )
        }
        .sorted { $0.millisecondsPerSecond > $1.millisecondsPerSecond }
    }
}

final class PerformanceLog: @unchecked Sendable {
    static let shared = PerformanceLog()

    private let queue = DispatchQueue(label: "perf.log", qos: .utility)
    private let url: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("perf.log")
    private var handle: FileHandle?
    private var written = 0
    private let maximumBytes = 4 * 1024 * 1024

    private init() {}

    func append(_ line: String) {
        queue.async { [self] in
            if handle == nil {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: url)
                handle?.seekToEndOfFile()
                written = Int(handle?.offsetInFile ?? 0)
            }
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if written + data.count > maximumBytes {
                try? handle?.truncate(atOffset: 0)
                written = 0
            }
            handle?.write(data)
            written += data.count
        }
    }

    func startSession() {
        let formatter = ISO8601DateFormatter()
        append("=== Session \(formatter.string(from: Date())) ===")
        append("time fps/target frameMax blockMax blockAvg hitches playing pos lagMax lagAvg switches | sections…")
    }
}

final class MainThreadStallMonitor: @unchecked Sendable {
    static let shared = MainThreadStallMonitor()

    private let queue = DispatchQueue(label: "perf.stall", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var lock = os_unfair_lock_s()
    private var worstLatency: Double = 0
    private var sumLatency: Double = 0
    private var samples = 0

    private init() {}

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(20))
            source.setEventHandler { [self] in
                let sent = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async { [self] in
                    let latency = CFAbsoluteTimeGetCurrent() - sent
                    os_unfair_lock_lock(&lock)
                    worstLatency = max(worstLatency, latency)
                    sumLatency += latency
                    samples += 1
                    os_unfair_lock_unlock(&lock)
                }
            }
            source.resume()
            timer = source
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    func drain() -> (worst: Double, average: Double) {
        os_unfair_lock_lock(&lock)
        let result = (
            worstLatency * 1000,
            samples > 0 ? sumLatency / Double(samples) * 1000 : 0
        )
        worstLatency = 0
        sumLatency = 0
        samples = 0
        os_unfair_lock_unlock(&lock)
        return result
    }
}
