import Accelerate
import Foundation

struct AudioFrame: Equatable, Sendable {
    var bands: [Float]
    var waveform: [Float]
    var energy: Float
    var beat: Float
    var timestamp: TimeInterval
    static let zero = AudioFrame(bands: Array(repeating: 0, count: 24), waveform: Array(repeating: 0, count: 64), energy: 0, beat: 0, timestamp: 0)
    func isFresh(at time: TimeInterval) -> Bool { timestamp > 0 && time >= timestamp && time - timestamp < 0.75 }
}

// Owned by one serial audio queue. PCM stays here; only small numeric frames leave it.
final class SpectrumAnalyzer: @unchecked Sendable {
    static let sampleCount = 2048
    private let setup: FFTSetup
    private var window = [Float](repeating: 0, count: sampleCount)
    private var smoothed = [Float](repeating: 0, count: 24)
    private var bassAverage: Float = 0
    private var previousBass: Float = 0
    private var beat: Float = 0
    private var lastBeat = -Double.infinity
    private var lastFrame = -Double.infinity

    init() {
        setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.sampleCount), Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_destroy_fftsetup(setup) }

    func analyze(_ input: [Float], sampleRate: Double, at time: TimeInterval) -> AudioFrame {
        guard input.count == Self.sampleCount, sampleRate.isFinite, sampleRate >= 8000, time.isFinite else { return .zero }
        let samples = input.map { $0.isFinite ? min(1, max(-1, $0)) : 0 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        var windowed = [Float](repeating: 0, count: Self.sampleCount)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(samples.count))
        var real = [Float](repeating: 0, count: Self.sampleCount / 2)
        var imaginary = real
        var power = real
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                windowed.withUnsafeBufferPointer { buffer in
                    buffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.sampleCount / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.sampleCount / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, 11, FFTDirection(FFT_FORWARD))
                split.imagp[0] = 0 // Real FFT packs the Nyquist component here.
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(power.count))
            }
        }
        let binWidth = sampleRate / Double(Self.sampleCount)
        let upper = min(16000, sampleRate * 0.48)
        var levels = [Float](repeating: 0, count: 24)
        for band in levels.indices {
            let lowerFrequency = 40 * pow(upper / 40, Double(band) / 24)
            let upperFrequency = 40 * pow(upper / 40, Double(band + 1) / 24)
            let lowerBin = max(1, min(power.count - 1, Int(lowerFrequency / binWidth)))
            let upperBin = min(power.count, max(lowerBin + 1, Int(ceil(upperFrequency / binWidth))))
            let peak = power[lowerBin..<upperBin].max() ?? 0
            let amplitude = sqrt(max(0, peak)) / Float(Self.sampleCount)
            let normalized = min(1, max(0, (20 * log10(max(0.000001, amplitude)) + 60) / 60))
            let rate: Float = normalized > smoothed[band] ? 0.75 : 0.24
            smoothed[band] += (normalized - smoothed[band]) * rate
            levels[band] = smoothed[band]
        }
        let bassEnd = min(power.count, max(2, Int(180 / binWidth)))
        let bass = sqrt(power[1..<bassEnd].reduce(0, +)) / Float(Self.sampleCount)
        let elapsed = max(0, min(1, time - lastFrame))
        beat *= Float(exp(-elapsed * 8))
        if rms > 0.003, bass > max(0.006, bassAverage * 1.5), bass > previousBass * 1.15, time - lastBeat > 0.18 {
            beat = 1; lastBeat = time
        }
        bassAverage += (bass - bassAverage) * 0.08
        previousBass = bass; lastFrame = time
        // Peak-preserving envelope: unlike taking every nth sample, transients remain visible.
        let waveform = (0..<64).map { index -> Float in
            let range = samples[(index * 32)..<((index + 1) * 32)]
            return range.max(by: { abs($0) < abs($1) }) ?? 0
        }
        return AudioFrame(bands: levels, waveform: waveform, energy: min(1, rms), beat: beat, timestamp: time)
    }
}
