import AppKit
import Combine
import SwiftUI

@MainActor final class SystemAppearance {
    private let popovers: [NSPopover]
    private var observation: NSKeyValueObservation?
    private var subscription: AnyCancellable?
    private var mode: AppearanceMode = .auto
    init(popovers: [NSPopover], preferences: AppPreferences? = nil) {
        self.popovers = popovers
        mode = preferences?.appearance ?? .auto
        update()
        subscription = preferences?.$appearance.sink { [weak self] mode in
            self?.mode = mode; self?.update()
        }
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.update() }
        }
    }
    private func update() {
        let appearance = switch mode {
        case .auto: NSApp.effectiveAppearance
        case .light: NSAppearance(named: .aqua)!
        case .dark: NSAppearance(named: .darkAqua)!
        }
        for popover in popovers { popover.appearance = appearance }
    }
}

// Dynamic NSColors resolve against the hosting window's current system appearance.
enum Palette {
    static let ink = adaptive("Background", light: (0.965, 0.977, 0.970), dark: (0.055, 0.071, 0.065))
    static let surface = adaptive("Surface", light: (0.995, 1.0, 0.997), dark: (0.10, 0.125, 0.113))
    static let raised = adaptive("Raised", light: (0.910, 0.937, 0.922), dark: (0.145, 0.17, 0.15))
    static let green = adaptive("Accent", light: (0.075, 0.455, 0.175), dark: (0.42, 0.94, 0.49))
    static let onAccent = adaptive("OnAccent", light: (1, 1, 1), dark: (0.055, 0.071, 0.065))
    static let primary = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let border = adaptive("Border", light: (0.08, 0.16, 0.11), dark: (1, 1, 1), lightAlpha: 0.12, darkAlpha: 0.09)
    static let sheen = adaptive("Sheen", light: (1, 1, 1), dark: (1, 1, 1), lightAlpha: 0.85, darkAlpha: 0.07)
    static let shadow = adaptive("Shadow", light: (0.04, 0.14, 0.08), dark: (0, 0, 0), lightAlpha: 0.12, darkAlpha: 0.3)
    static let brand = Color(red: 0.42, green: 0.94, blue: 0.49)
    static let onBrand = Color(red: 0.035, green: 0.095, blue: 0.050)

    private static func adaptive(_ name: String, light: (Double, Double, Double), dark: (Double, Double, Double), lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("PlayMenu.\(name)")) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

enum Motion {
    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.78)
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.62)
    static let soft = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static func animation(reduced: Bool) -> Animation? { reduced ? .easeOut(duration: 0.12) : spring }
    static func runs(playing: Bool, presented: Bool, reduced: Bool) -> Bool { playing && presented && !reduced }
    static func bars(at time: Double, playing: Bool) -> [Double] {
        guard playing else { return [0.16, 0.16, 0.16, 0.16, 0.16] }
        return (0..<5).map { index in
            let phase = Double(index) * 1.37
            let wave = sin(time * (3.2 + Double(index) * 0.43) + phase)
            let detail = sin(time * 6.3 + phase * 1.8) * 0.12
            return min(1, max(0.18, 0.55 + wave * 0.29 + detail))
        }
    }
}

private struct MotionActiveKey: EnvironmentKey { static let defaultValue = false }
private struct MotionReducedKey: EnvironmentKey { static let defaultValue: Bool? = nil }
extension EnvironmentValues {
    var motionActive: Bool {
        get { self[MotionActiveKey.self] }
        set { self[MotionActiveKey.self] = newValue }
    }
    var motionReduced: Bool {
        get { self[MotionReducedKey.self] ?? accessibilityReduceMotion }
        set { self[MotionReducedKey.self] = newValue }
    }
}

// A playback indicator, not an audio meter: Spotify supplies playback state, not PCM audio.
// Only this small shape updates on a frame tick; it never publishes into app state.
struct PlayingWaveform: View {
    let playing: Bool
    var color: Color = Palette.green
    var width: CGFloat = 18
    var height: CGFloat = 14
    @Environment(\.motionActive) private var presented
    @Environment(\.motionReduced) private var reduceMotion
    private var running: Bool { Motion.runs(playing: playing, presented: presented, reduced: reduceMotion) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { context in
            let values = Motion.bars(at: running ? context.date.timeIntervalSinceReferenceDate : 0.6, playing: playing)
            WaveformShape(levels: BarLevels(values)).fill(color)
                .animation(reduceMotion ? nil : Motion.soft, value: playing)
        }.frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

struct BarLevels: VectorArithmetic {
    var values: SIMD8<Double>
    init(_ levels: [Double]) { values = SIMD8(levels[0], levels[1], levels[2], levels[3], levels[4], 0, 0, 0) }
    private init(_ values: SIMD8<Double>) { self.values = values }
    static let zero = BarLevels(.zero)
    static func + (lhs: BarLevels, rhs: BarLevels) -> BarLevels { BarLevels(lhs.values + rhs.values) }
    static func - (lhs: BarLevels, rhs: BarLevels) -> BarLevels { BarLevels(lhs.values - rhs.values) }
    mutating func scale(by rhs: Double) { values *= rhs }
    var magnitudeSquared: Double { (0..<5).reduce(0) { $0 + values[$1] * values[$1] } }
}

private struct WaveformShape: Shape {
    var levels: BarLevels
    var animatableData: BarLevels { get { levels } set { levels = newValue } }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let gap = rect.width * 0.105, width = (rect.width - gap * 4) / 5
        for index in 0..<5 {
            let height = max(width, rect.height * levels.values[index])
            path.addRoundedRect(in: CGRect(x: rect.minX + CGFloat(index) * (width + gap), y: rect.midY - height / 2, width: width, height: height), cornerSize: CGSize(width: width / 2, height: width / 2))
        }
        return path
    }
}

struct PlayerGlow: View {
    let playing: Bool
    @Environment(\.motionActive) private var presented
    @Environment(\.motionReduced) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    private var running: Bool { Motion.runs(playing: playing, presented: presented, reduced: reduceMotion) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !running)) { context in
            let phase = running ? context.date.timeIntervalSinceReferenceDate * 0.35 : 0
            Canvas { canvas, size in
                canvas.addFilter(.blur(radius: 25))
                let x = size.width * (0.2 + sin(phase) * 0.09)
                let y = size.height * (0.28 + cos(phase * 0.8) * 0.12)
                canvas.fill(Path(ellipseIn: CGRect(x: x - 65, y: y - 40, width: 160, height: 120)), with: .color(Palette.green.opacity(scheme == .dark ? 0.22 : 0.10)))
                canvas.fill(Path(ellipseIn: CGRect(x: size.width * 0.75 + cos(phase) * 22, y: size.height * 0.7, width: 100, height: 70)), with: .color(.mint.opacity(scheme == .dark ? 0.10 : 0.06)))
            }
        }.opacity(playing ? 1 : 0.25)
            .animation(Motion.animation(reduced: reduceMotion), value: playing)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct SymbolFeedback: ViewModifier {
    let trigger: Int
    @Environment(\.motionReduced) private var reduceMotion
    func body(content: Content) -> some View {
        if reduceMotion { content.contentTransition(.opacity) }
        else { content.contentTransition(.symbolEffect(.replace)).symbolEffect(.bounce, options: .speed(1.4), value: trigger) }
    }
}

struct MenuEntrance: ViewModifier {
    let visible: Bool
    @Environment(\.motionReduced) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .scaleEffect(visible || reduceMotion ? 1 : 0.975, anchor: .top)
            .offset(y: visible || reduceMotion ? 0 : -7)
            .animation(Motion.animation(reduced: reduceMotion), value: visible)
    }
}

// A compact iOS-style scrubber. Visual feedback is local; network writes happen on release.
enum ScrubberMath {
    static func value(at x: Double, width: Double, range: ClosedRange<Double>) -> Double {
        let fraction = min(1, max(0, x / max(width, 1)))
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
    static func fraction(_ value: Double, range: ClosedRange<Double>) -> Double {
        min(1, max(0, (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 1)))
    }
}

struct MusicSlider: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    var valueDescription: String
    var smoothUpdates = false
    var step = 1.0
    var waveform: AudioVisualizer? = nil
    var playing = false
    let onEditingChanged: (Bool) -> Void
    @State private var dragging = false
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.motionReduced) private var reduceMotion
    @Environment(\.motionActive) private var presented
    private var expanded: Bool { dragging || hovering || focused }
    private var trackHeight: CGFloat { waveform == nil ? 18 : 30 }
    var body: some View {
        GeometryReader { geometry in
            let fraction = ScrubberMath.fraction(value, range: range)
            let thumb = waveform != nil ? (expanded ? 13.0 : 11.0) : (expanded ? 12.0 : 7.0)
            let tint = waveform == nil ? Palette.green : Palette.primary.opacity(0.9)
            ZStack(alignment: .leading) {
                if let waveform {
                    ProgressWaveform(visualizer: waveform, playing: playing)
                        .frame(width: geometry.size.width, height: 20)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: max(0, geometry.size.width * fraction))
                        }
                        .offset(y: -10)
                }
                Capsule().fill(Palette.muted.opacity(0.22)).frame(height: waveform != nil ? 2.5 : expanded ? 6 : 3.5)
                Capsule().fill(tint.gradient).frame(width: max(0, geometry.size.width * fraction), height: waveform != nil ? 2.5 : expanded ? 6 : 3.5)
                Circle().fill(.white).overlay(Circle().stroke(Palette.border))
                    .shadow(color: Palette.shadow, radius: expanded ? 4 : 1, y: 1)
                    .frame(width: thumb, height: thumb)
                    .offset(x: min(max(geometry.size.width * fraction - thumb / 2, 0), max(0, geometry.size.width - thumb)))
            }
            .frame(height: trackHeight)
            .offset(y: waveform == nil ? 0 : 6)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    guard enabled else { return }
                    if !dragging { dragging = true; focused = true; onEditingChanged(true) }
                    value = ScrubberMath.value(at: gesture.location.x, width: geometry.size.width, range: range)
                }
                .onEnded { gesture in
                    guard dragging else { return }
                    value = ScrubberMath.value(at: gesture.location.x, width: geometry.size.width, range: range)
                    dragging = false; focused = false; onEditingChanged(false)
                })
            .animation(reduceMotion ? nil : Motion.press, value: expanded)
            .animation(smoothUpdates && presented && !dragging && !reduceMotion ? .linear(duration: 0.95) : nil, value: value)
        }.frame(height: trackHeight).opacity(enabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .onChange(of: focused) { _, value in preferences.adjustingSlider = value }
            .onChange(of: presented) { _, visible in
                if !visible {
                    focused = false; hovering = false
                    if dragging { dragging = false; onEditingChanged(false) }
                }
            }
            .focusable(enabled).focused($focused).focusEffectDisabled()
            .onMoveCommand { direction in
                guard enabled else { return }
                if direction == .right || direction == .up { adjust(step) }
                else if direction == .left || direction == .down { adjust(-step) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityValue(valueDescription)
            .accessibilityHint(waveform == nil ? "" : "Waveform motion is decorative unless local audio capture is enabled in Settings")
            .accessibilityAdjustableAction { direction in adjust(direction == .increment ? step : -step) }
            .help(label)
    }
    private func adjust(_ delta: Double) {
        guard enabled else { return }
        onEditingChanged(true)
        value = min(range.upperBound, max(range.lowerBound, value + delta))
        onEditingChanged(false)
    }
}
