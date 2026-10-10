import CoreAudio
import Foundation

protocol AudioCapturing: Sendable {
    func start(onFrame: @escaping @Sendable (AudioFrame) -> Void) async throws
    func stop() async
}

enum AudioCaptureError: LocalizedError {
    case unsupported, spotifyNotRunning, format, operation(OSStatus)
    var errorDescription: String? {
        switch self {
        case .unsupported: "Live audio needs macOS 14.2 or later."
        case .spotifyNotRunning: "Open the Spotify desktop app and play music on this Mac."
        case .format: "Spotify’s audio format is unavailable. Try another output device."
        case .operation(let status): "Audio access is unavailable (\(status)). Allow PlayMenu in System Settings → Privacy & Security → Screen & System Audio Recording, then retry."
        }
    }
}

actor SpotifyAudioCapture: AudioCapturing {
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.playmenu.audio-analysis", qos: .userInitiated)

    func start(onFrame: @escaping @Sendable (AudioFrame) -> Void) throws {
        stop()
        guard #available(macOS 14.2, *) else { throw AudioCaptureError.unsupported }
        do {
            let processes = try spotifyProcesses()
            guard !processes.isEmpty else { throw AudioCaptureError.spotifyNotRunning }
            let description = CATapDescription(stereoMixdownOfProcesses: processes)
            description.name = "PlayMenu Spotify Visualizer"
            description.uuid = UUID()
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tap))
            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address = property(kAudioTapPropertyFormat)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mSampleRate >= 8000 else { throw AudioCaptureError.format }
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "PlayMenu Audio Analysis",
                kAudioAggregateDeviceUIDKey: "com.playmenu.visualizer.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device))
            let processor = AudioSampleProcessor(sampleRate: format.mSampleRate, onFrame: onFrame)
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, queue) { _, input, _, _, _ in
                processor.consume(input)
            })
            try check(AudioDeviceStart(device, ioProc))
        } catch { stop(); throw error }
    }

    func stop() {
        if device != 0 {
            if let ioProc { AudioDeviceStop(device, ioProc); AudioDeviceDestroyIOProcID(device, ioProc) }
            AudioHardwareDestroyAggregateDevice(device)
        }
        if #available(macOS 14.2, *), tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        ioProc = nil; device = 0; tap = 0
    }

    @available(macOS 14.2, *) private func spotifyProcesses() throws -> [AudioObjectID] {
        var address = property(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size))
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !ids.isEmpty else { return [] }
        let result = ids.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, buffer.baseAddress!)
        }
        try check(result)
        return ids.filter { id in
            var bundleAddress = property(kAudioProcessPropertyBundleID)
            var bundleID: Unmanaged<CFString>?
            var length = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &length, &bundleID) == noErr, let bundleID else { return false }
            let value = bundleID.takeRetainedValue() as String
            return value == "com.spotify.client" || value.hasPrefix("com.spotify.client.")
        }
    }
    private func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private func check(_ status: OSStatus) throws { if status != noErr { throw AudioCaptureError.operation(status) } }
}

// The HAL dispatches this on one serial queue; no buffers or pointers escape the callback.
private final class AudioSampleProcessor: @unchecked Sendable {
    private let analyzer = SpectrumAnalyzer()
    private let sampleRate: Double
    private let onFrame: @Sendable (AudioFrame) -> Void
    private var samples: [Float] = []
    private var lastEmission = -Double.infinity
    init(sampleRate: Double, onFrame: @escaping @Sendable (AudioFrame) -> Void) {
        self.sampleRate = sampleRate; self.onFrame = onFrame
        samples.reserveCapacity(SpectrumAnalyzer.sampleCount)
    }
    func consume(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard !buffers.isEmpty else { return }
        let frameCount = buffers.map { Int($0.mDataByteSize) / (MemoryLayout<Float>.size * max(1, Int($0.mNumberChannels))) }.min() ?? 0
        guard frameCount > 0, buffers.allSatisfy({ $0.mData != nil }) else { return }
        let channels = max(1, buffers.reduce(0) { $0 + Int($1.mNumberChannels) })
        for frame in 0..<frameCount {
            var mono: Float = 0
            for buffer in buffers {
                let data = buffer.mData!.assumingMemoryBound(to: Float.self)
                for channel in 0..<Int(buffer.mNumberChannels) { mono += data[frame * Int(buffer.mNumberChannels) + channel] }
            }
            samples.append(mono / Float(channels))
            if samples.count == SpectrumAnalyzer.sampleCount {
                let time = Date.timeIntervalSinceReferenceDate
                if time - lastEmission >= 1.0 / 30 {
                    onFrame(analyzer.analyze(samples, sampleRate: sampleRate, at: time))
                    lastEmission = time
                }
                samples.removeAll(keepingCapacity: true)
            }
        }
    }
}
