import Foundation

/// On-device rate limiting for AI requests, so a stuck button, a retry loop or a
/// modified build can't hammer the proxy. Sliding windows per feature plus an
/// overall ceiling, and a pause after the server reports it is busy. There is no
/// daily cap: normal use never notices it.
final class AIUsage: @unchecked Sendable {
    enum Feature: String, CaseIterable, Sendable {
        case coach, food, clipReview, styleStudy, program, nutrition, workout, debrief
        /// (requests, seconds) windows. All must have room for a request to go out.
        var windows: [(count: Int, seconds: TimeInterval)] {
            switch self {
            case .coach: [(8, 60), (60, 900)]
            case .food: [(6, 60), (40, 900)]
            case .clipReview, .styleStudy: [(2, 60), (8, 900)]
            case .program, .nutrition: [(3, 60), (10, 900)]
            case .workout: [(4, 60), (20, 900)]
            case .debrief: [(4, 60), (30, 900)]
            }
        }
        /// Minimum time between two requests of this feature (double taps).
        var minimumGap: TimeInterval {
            switch self {
            case .coach, .food, .workout, .debrief: 1.5
            case .clipReview, .styleStudy, .program, .nutrition: 5
            }
        }
    }
    /// Every feature together.
    static let overall: [(count: Int, seconds: TimeInterval)] = [(15, 60), (120, 900)]
    static let busyCooldown: TimeInterval = 60

    enum Limit: LocalizedError, Equatable {
        case tooSoon(seconds: Int), coolingDown(seconds: Int)
        var errorDescription: String? {
            switch self {
            case .tooSoon(let s): String(localized: "That's a lot of requests in a short time. Try again in \(s) s.")
            case .coolingDown(let s): String(localized: "Your coach is busy. Try again in \(s) s.")
            }
        }
    }

    static let shared = AIUsage()
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults; self.now = now
    }

    private func key(_ name: String) -> String { "ai.rate.\(name)" }
    private func stamps(_ name: String, after cutoff: Double) -> [Double] { (defaults.array(forKey: key(name)) as? [Double] ?? []).filter { $0 > cutoff } }

    /// Seconds until a request fits every window, or 0 if it fits now.
    private func wait(_ stamps: [Double], _ windows: [(count: Int, seconds: TimeInterval)], at t: Double) -> Double {
        windows.map { w in
            let inWindow = stamps.filter { $0 > t - w.seconds }.sorted()
            return inWindow.count < w.count ? 0 : inWindow[inWindow.count - w.count] + w.seconds - t
        }.max() ?? 0
    }

    /// Reserves one request or throws how long to wait. Call right before sending.
    func begin(_ f: Feature) throws {
        try lock.withLock {
            let t = now().timeIntervalSince1970
            let busyUntil = defaults.double(forKey: key("busyUntil"))
            if busyUntil > t { throw Limit.coolingDown(seconds: Int((busyUntil - t).rounded(.up))) }
            let horizon = t - 900
            let mine = stamps(f.rawValue, after: horizon), all = stamps("all", after: horizon)
            var delay = max(wait(mine, f.windows, at: t), wait(all, Self.overall, at: t))
            if let last = mine.max(), t - last < f.minimumGap { delay = max(delay, f.minimumGap - (t - last)) }
            if delay > 0 { throw Limit.tooSoon(seconds: max(1, Int(delay.rounded(.up)))) }
            defaults.set(mine + [t], forKey: key(f.rawValue))
            defaults.set(all + [t], forKey: key("all"))
        }
    }
    /// The server said it is at capacity: pause every feature for a minute.
    func noteBusy() { lock.withLock { defaults.set(now().timeIntervalSince1970 + Self.busyCooldown, forKey: key("busyUntil")) } }
}
