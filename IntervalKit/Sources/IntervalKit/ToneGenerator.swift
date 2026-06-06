import Foundation

/// Synthesizes short sine-wave tones in code so the app needs zero bundled
/// audio assets. A linear fade in/out over the first/last 10% of samples
/// prevents the audible "click" a hard-edged tone would produce.
public enum ToneGenerator {
    public static func sineWaveSamples(
        frequency: Double,
        duration: TimeInterval,
        sampleRate: Double = 44_100,
        amplitude: Float = 0.6
    ) -> [Float] {
        let frameCount = Int(duration * sampleRate)
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { frame in
            let phase = 2.0 * Double.pi * frequency * (Double(frame) / sampleRate)
            let envelope = fadeEnvelope(frame: frame, totalFrames: frameCount)
            return Float(sin(phase)) * amplitude * envelope
        }
    }

    private static func fadeEnvelope(frame: Int, totalFrames: Int) -> Float {
        let fadeFrames = max(1, totalFrames / 10)
        if frame < fadeFrames {
            return Float(frame) / Float(fadeFrames)
        }
        if frame > totalFrames - fadeFrames {
            return Float(totalFrames - frame) / Float(fadeFrames)
        }
        return 1.0
    }
}
