import AVFoundation
import IntervalKit

/// Plays synthesized chime tones through an `AVAudioEngine` configured for
/// background playback, so the bell still sounds with the screen locked.
@MainActor
final class ChimePlayer {
    enum ChimeKind {
        case transition
        case workoutComplete
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private var buffers: [ChimeKind: AVAudioPCMBuffer] = [:]
    private var isEngineRunning = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffers[.transition] = makeBuffer(samples: ToneGenerator.sineWaveSamples(frequency: 880, duration: 0.18, sampleRate: sampleRate))
        buffers[.workoutComplete] = makeBuffer(samples: fanfareSamples())
    }

    /// Call once before the first chime of a workout. Configures the shared
    /// session for background playback and activates it.
    func configureSessionForBackgroundPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    func play(_ kind: ChimeKind) {
        guard let buffer = buffers[kind] else { return }
        if !isEngineRunning {
            try? engine.start()
            isEngineRunning = true
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    /// A short three-note ascending chime (C5-E5-G5) for "workout complete".
    private func fanfareSamples() -> [Float] {
        [523.25, 659.25, 783.99].flatMap {
            ToneGenerator.sineWaveSamples(frequency: $0, duration: 0.16, sampleRate: sampleRate)
        }
    }

    private func makeBuffer(samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = buffer.floatChannelData?[0]
        for (index, sample) in samples.enumerated() {
            channel?[index] = sample
        }
        return buffer
    }
}
