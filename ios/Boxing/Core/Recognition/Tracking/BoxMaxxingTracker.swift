import Foundation

/// Faithful landmark/normalization port of functions27640,37435–37438.
/// Separate from presence, body calibration, candidate detection and technique assessment.
struct BoxMaxxingTracker: Sendable {
    struct Configuration: Codable, Sendable {
        var minScore = 0.3, minArmScore = 0.2, armObservationGraceMs = 150.0
        var weakArmScore = 0.1, weakMaxJump = 0.6, holdMs = 250.0
        var minCutoffHz = 2.5, beta = 30.0, dCutoffHz = 4.0, swapMargin = 0.7
        var minScale = 0.04, torsoRatio = 1.5, maxScaleJump = 0.3
        var scaleTauS = 0.0, featureScaleTauS = 0.5, minDtS = 1.0 / 120.0, maxDtS = 0.5
    }
    struct RawPoint: Codable, Sendable { var x: Double; var y: Double; var score: Double }
    struct Input: Codable, Sendable { var tMs: Double; var width: Double; var height: Double; var keypoints: [RawPoint?] }
    struct Centre: Codable, Sendable { var x: Double; var y: Double }
    struct Output: Codable, Sendable {
        var tMs: Double; var dtS: Double; var points: [BoxMaxxingFeaturePoint]
        var scale: Double; var scaleSlow: Double; var centre: Centre
        var shoulderTiltDeg: Double; var confident: Int; var lost: Bool; var shoulderWidth: Double
        var featurePose: BoxMaxxingFeaturePose { .init(tMs: tMs, lost: lost, points: points) }
    }
    private struct Track: Sendable {
        var fx: BoxMaxxingOneEuro; var fy: BoxMaxxingOneEuro
        var seen = false, score = 0.0, x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
        var lastSeenMs = -Double.infinity, lastStrongMs = -Double.infinity
    }
    let configuration: Configuration
    private var tracks: [Track]
    private(set) var torsoRatio: Double
    private(set) var previousMs: Double?
    private(set) var scaleHat: Double?
    private(set) var scaleSlowHat: Double?

    init(configuration: Configuration = .init()) {
        self.configuration = configuration; torsoRatio = configuration.torsoRatio
        let cfg = BoxMaxxingOneEuro.Configuration(minCutoffHz: configuration.minCutoffHz, beta: configuration.beta, dCutoffHz: configuration.dCutoffHz)
        tracks = (0..<17).map { _ in Track(fx: .init(configuration: cfg), fy: .init(configuration: cfg)) }
    }
    mutating func setTorsoRatio(_ value: Double) {
        if value.isFinite && value > 0.5 && value < 4 { torsoRatio = value }
    }
    mutating func reset() {
        for i in tracks.indices {
            tracks[i].fx.reset(); tracks[i].fy.reset(); tracks[i].seen = false
            tracks[i].score = 0; tracks[i].vx = 0; tracks[i].vy = 0
            tracks[i].lastSeenMs = -.infinity; tracks[i].lastStrongMs = -.infinity
        }
        previousMs = nil; scaleHat = nil; scaleSlowHat = nil
    }
    mutating func update(_ input: Input, armed: Bool = false) throws -> Output {
        guard input.keypoints.count == 17, input.tMs.isFinite, input.width.isFinite, input.height.isFinite else { throw BoxMaxxingFeatureError.pointCount(input.keypoints.count) }
        let c = configuration
        let aspect = input.width > 0 && input.height > 0 ? input.width / input.height : 1
        let dt = previousMs.map { min(c.maxDtS, max(c.minDtS, (input.tMs - $0) / 1000)) } ?? (c.minDtS * 4)
        previousMs = input.tMs
        let shouldersObserved = [5, 6].allSatisfy { i in
            guard let p = input.keypoints[i] else { return false }
            return p.score >= c.minScore && p.x.isFinite && p.y.isFinite
        }
        let armThreshold = armed && shouldersObserved ? min(c.minScore, c.minArmScore) : c.minScore
        let weakArms = armed && shouldersObserved && c.weakArmScore < 1
        let armIDs = Set([7, 8, 9, 10])
        var observations = [BoxMaxxingFeaturePoint?](repeating: nil, count: 17)
        var weak = observations
        for i in input.keypoints.indices {
            let elapsed = input.tMs - tracks[i].lastStrongMs
            let threshold = armIDs.contains(i) && elapsed >= 0 && elapsed <= c.armObservationGraceMs ? armThreshold : c.minScore
            guard let raw = input.keypoints[i], raw.x.isFinite, raw.y.isFinite else { continue }
            let point = BoxMaxxingFeaturePoint(x: raw.x * aspect, y: raw.y, score: raw.score)
            observations[i] = point.score >= threshold ? point : nil
            weak[i] = observations[i] == nil && weakArms && armIDs.contains(i) && point.score >= c.weakArmScore ? point : nil
        }
        for (left, right) in [(9, 10), (7, 8)] {
            guard let a = observations[left], let b = observations[right], tracks[left].seen, tracks[right].seen else { continue }
            let pxA = tracks[left].x + tracks[left].vx * dt, pyA = tracks[left].y + tracks[left].vy * dt
            let pxB = tracks[right].x + tracks[right].vx * dt, pyB = tracks[right].y + tracks[right].vy * dt
            let keep = hypot(a.x - pxA, a.y - pyA) + hypot(b.x - pxB, b.y - pyB)
            let swap = hypot(b.x - pxA, b.y - pyA) + hypot(a.x - pxB, a.y - pyB)
            if swap < keep * c.swapMargin { observations[left] = b; observations[right] = a }
        }
        var count = 0
        var absolute = [BoxMaxxingFeaturePoint]()
        for i in tracks.indices {
            var t = tracks[i]
            if let p = observations[i] {
                let recent = t.seen && input.tMs - t.lastSeenMs <= c.holdMs
                if !recent { t.fx.reset(); t.fy.reset(); t.vx = 0; t.vy = 0 }
                let x = t.fx.filter(p.x, dtS: dt), y = t.fy.filter(p.y, dtS: dt)
                if recent { t.vx = (x - t.x) / dt; t.vy = (y - t.y) / dt }
                t.x = x; t.y = y; t.score = p.score; t.lastSeenMs = input.tMs
                if p.score >= c.minScore { t.lastStrongMs = input.tMs }
                t.seen = true; count += 1
                absolute.append(.init(x: t.x, y: t.y, score: p.score, held: false))
            } else {
                let held = t.seen && input.tMs - t.lastSeenMs <= c.holdMs
                var acceptedWeak = false
                if let p = weak[i], held, let scaleHat {
                    let distance = hypot(p.x - (t.x + t.vx * dt), p.y - (t.y + t.vy * dt))
                    if distance <= c.weakMaxJump * scaleHat {
                        let x = t.fx.filter(p.x, dtS: dt), y = t.fy.filter(p.y, dtS: dt)
                        t.vx = (x - t.x) / dt; t.vy = (y - t.y) / dt; t.x = x; t.y = y
                        absolute.append(.init(x: t.x, y: t.y, score: p.score, held: true)); acceptedWeak = true
                    }
                }
                if !acceptedWeak {
                    t.vx *= 0.5; t.vy *= 0.5
                    absolute.append(.init(x: t.x, y: t.y, score: held ? t.score : 0, held: true))
                }
            }
            tracks[i] = t
        }
        let ls = absolute[5], rs = absolute[6], lh = absolute[11], rh = absolute[12]
        let shoulders = ls.score > 0 && rs.score > 0
        let width = shoulders ? hypot(ls.x - rs.x, ls.y - rs.y) : 0
        let torso = shoulders && lh.score > 0 && rh.score > 0 ? hypot((lh.x + rh.x) / 2 - (ls.x + rs.x) / 2, (lh.y + rh.y) / 2 - (ls.y + rs.y) / 2) : 0
        let measuredScale = shoulders ? max(width, torso / torsoRatio) : 0
        var lost = !shoulders || measuredScale < c.minScale
        if !lost {
            if let old = scaleHat {
                if abs(measuredScale - old) / old > c.maxScaleJump { scaleHat = measuredScale; lost = true }
                else {
                    let alpha = armed && c.scaleTauS > 0 ? 1 - exp(-dt / c.scaleTauS) : 0.2
                    scaleHat = (1 - alpha) * old + alpha * measuredScale
                }
            } else { scaleHat = measuredScale }
            if let old = scaleSlowHat, armed, c.featureScaleTauS > 0, !lost {
                let alpha = 1 - exp(-dt / c.featureScaleTauS)
                scaleSlowHat = (1 - alpha) * old + alpha * measuredScale
            } else { scaleSlowHat = scaleHat }
        }
        let scale = scaleHat ?? measuredScale, slow = scaleSlowHat ?? scale
        let centre = Centre(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let tilt = shoulders ? atan2(rs.y - ls.y, rs.x - ls.x) * 180 / Double.pi : 0
        let inverse = scale > 0 ? 1 / scale : 0
        let normalized = absolute.map { BoxMaxxingFeaturePoint(x: ($0.x - centre.x) * inverse, y: ($0.y - centre.y) * inverse, score: $0.score, held: $0.held) }
        return Output(tMs: input.tMs, dtS: dt, points: normalized, scale: scale, scaleSlow: slow, centre: centre, shoulderTiltDeg: tilt, confident: count, lost: lost, shoulderWidth: width)
    }
}
