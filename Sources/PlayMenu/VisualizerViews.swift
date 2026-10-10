import SwiftUI

struct LivePlayingIndicator: View {
    @ObservedObject var visualizer: AudioVisualizer
    let playing: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.motionActive) private var presented
    @Environment(\.motionReduced) private var reduced
    var body: some View {
        if playing, presented, !reduced, visualizer.status == .listening, visualizer.frame.isFresh(at: Date.timeIntervalSinceReferenceDate), visualizer.frame.energy > 0.0001, visualizer.frame.bands.count >= 5 {
            let bands = visualizer.frame.bands
            let levels = (0..<5).map { group -> Float in
                let subset = bands[(group * bands.count / 5)..<((group + 1) * bands.count / 5)]
                return subset.max() ?? 0
            }
            SpectrumShape(levels: levels).fill(Palette.green).frame(width: width, height: height).accessibilityHidden(true)
        } else { PlayingWaveform(playing: playing, width: width, height: height) }
    }
}

// Filled, overlapping waves sit directly on the seek rail, clipped to elapsed time.
// Measured audio controls their height; the fallback is a decorative playback animation.
struct ProgressWaveform: View {
    @ObservedObject var visualizer: AudioVisualizer
    let playing: Bool
    @State private var envelope = WaveEnvelope()
    @Environment(\.motionActive) private var presented
    @Environment(\.motionReduced) private var reduced
    private var running: Bool { Motion.runs(playing: playing, presented: presented, reduced: reduced) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !running)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { layer in
                    ProgressWaveShape(levels: ProgressWaveMath.levels(at: time, active: running, amplitude: envelope.value(at: time), layer: layer))
                        .fill(Palette.primary.opacity([0.16, 0.28, 0.85][layer]))
                }
            }
        }
        .onChange(of: visualizer.frame, initial: true) { _, frame in
            let time = Date.timeIntervalSinceReferenceDate
            let measured = visualizer.status == .listening && frame.isFresh(at: time) && frame.energy > 0.0001
            let target = measured ? min(0.95, 0.24 + sqrt(Double(frame.energy)) * 1.15 + Double(frame.beat) * 0.08) : 0.62
            envelope.retarget(to: target, at: time)
        }
        .onChange(of: running) { _, active in if !active { envelope = WaveEnvelope() } }
        // Parent seek/press animations must not restart the continuous wave motion.
        .transaction { $0.animation = nil }
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}

// Interpolate continuously between capture frames, even when their timing is irregular.
// No PCM sample changes the spatial profile; audio only changes this slow amplitude envelope.
struct WaveEnvelope {
    private var origin = 0.62
    private var target = 0.62
    private var timestamp = 0.0
    func value(at time: Double) -> Double {
        guard time.isFinite else { return origin }
        let elapsed = max(0, time - timestamp)
        let duration = target > origin ? 0.30 : 0.50
        return target + (origin - target) * exp(-elapsed / duration)
    }
    mutating func retarget(to amplitude: Double, at time: Double) {
        guard amplitude.isFinite, time.isFinite else { return }
        origin = value(at: time)
        target = min(0.95, max(0.12, amplitude))
        timestamp = time
    }
}

enum ProgressWaveMath {
    static func levels(at time: Double, active: Bool, amplitude: Double, layer: Int) -> [Double] {
        guard active, time.isFinite, amplitude.isFinite else { return Array(repeating: 0, count: 80) }
        let speed = 0.85 + Double(layer) * 0.12
        let phase = (time * speed).truncatingRemainder(dividingBy: 2 * .pi)
        let driftPhase = (time * 0.14).truncatingRemainder(dividingBy: 2 * .pi)
        let gain = min(0.95, max(0, amplitude))
        return (0..<80).map { index in
            let x = Double(index) / 79
            // Broad, rounded crests travel horizontally with independent layer phases.
            let crest = pow((sin(x * .pi * (7 + Double(layer) * 0.45) - phase + Double(layer) * 1.8) + 1) / 2, 1.6)
            let drift = 0.72 + 0.28 * (sin(x * 7 + driftPhase + Double(layer)) + 1) / 2
            return min(1, max(0, sin(x * .pi) * crest * drift * gain))
        }
    }
}

private struct ProgressWaveShape: Shape {
    let levels: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard levels.count > 1 else { return path }
        let points = levels.indices.map { index in
            CGPoint(x: rect.minX + CGFloat(index) / CGFloat(levels.count - 1) * rect.width,
                    y: rect.maxY - CGFloat(levels[index]) * rect.height)
        }
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1], current = points[index]
            path.addQuadCurve(to: CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2), control: previous)
        }
        path.addLine(to: points[points.count - 1])
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SpectrumShape: Shape {
    let levels: [Float]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(1, levels.count)
        let gap = min(3, rect.width / CGFloat(count) * 0.22)
        let width = max(1, (rect.width - gap * CGFloat(count - 1)) / CGFloat(count))
        for (index, level) in levels.enumerated() {
            let height = max(2, rect.height * CGFloat(level))
            path.addRoundedRect(in: CGRect(x: CGFloat(index) * (width + gap), y: rect.midY - height / 2, width: width, height: height), cornerSize: CGSize(width: 2, height: 2))
        }
        return path
    }
}

struct AudioBeatPulse: ViewModifier {
    @ObservedObject var visualizer: AudioVisualizer
    @Environment(\.motionActive) private var presented
    @Environment(\.motionReduced) private var reduced
    private var beat: Double {
        guard presented, !reduced, visualizer.frame.isFresh(at: Date.timeIntervalSinceReferenceDate) else { return 0 }
        return Double(visualizer.frame.beat)
    }
    func body(content: Content) -> some View {
        content.scaleEffect(1 + beat * 0.035)
            .shadow(color: Palette.green.opacity(beat * 0.4), radius: 4 + beat * 10)
            .animation(reduced ? nil : .easeOut(duration: 0.10), value: visualizer.frame.beat)
    }
}

struct LiveVisualizerSettings: View {
    @ObservedObject var visualizer: AudioVisualizer
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $preferences.liveVisualizer) {
                Text("Audio-reactive waveform").font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.small)
            Text("Match the progress-bar waves to Spotify on this Mac. Requires macOS 14.2+ and audio permission. Audio stays in memory.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if preferences.liveVisualizer {
                Text(visualizer.lastError ?? visualizer.status.message).font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
