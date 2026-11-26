import AVFoundation

/// Puffert gestreamtes 16-Bit-Mono-PCM komplett und spielt es ab – mit Pause, Spulen und Wiederholen.
/// Alle Methoden auf dem Main-Thread aufrufen.
final class StreamPlayer {
    static let sampleRate: Double = 44_100
    /// Vorrat, bevor die Wiedergabe startet bzw. nach einem Pufferunterlauf weiterläuft (0,4 s).
    static let startBuffer = Int(0.4 * sampleRate)

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: StreamPlayer.sampleRate, channels: 1)!

    private(set) var samples: [Float] = []
    private(set) var receivedAll = false
    private(set) var isPlaying = false

    private var segmentStart = 0   // Frame, ab dem das aktuelle Abspiel-Segment begann
    private var scheduledEnd = 0   // bis hierhin sind Puffer eingeplant
    private var pausedFrame = 0

    /// Pegel (0…1) für die Anzeige, auf dem Main-Thread geliefert.
    var onLevel: ((Float) -> Void)?

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            let n = Int(buffer.frameLength)
            for i in 0..<n { sum += ch[i] * ch[i] }
            let level = min(1, (sum / Float(n)).squareRoot() * 4)
            DispatchQueue.main.async { self?.onLevel?(level) }
        }
    }

    var frameCount: Int { samples.count }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    /// Position ohne Begrenzung (kann bei Pufferunterlauf über `scheduledEnd` hinauslaufen).
    private var rawFrame: Int {
        guard isPlaying, let t = node.lastRenderTime, let pt = node.playerTime(forNodeTime: t) else {
            return pausedFrame
        }
        return segmentStart + max(0, Int(pt.sampleTime))
    }

    var currentFrame: Int { isPlaying ? min(rawFrame, scheduledEnd) : pausedFrame }

    var isAtEnd: Bool { receivedAll && currentFrame >= samples.count }

    func reset() {
        node.stop()
        samples.removeAll()
        receivedAll = false
        isPlaying = false
        segmentStart = 0
        scheduledEnd = 0
        pausedFrame = 0
    }

    /// `data`: Int16 Little Endian, gerade Anzahl Bytes.
    func append(_ data: Data) {
        guard data.count >= 2 else { return }
        data.withUnsafeBytes { raw in
            let n = raw.count / 2
            samples.reserveCapacity(samples.count + n)
            for i in 0..<n {
                let s = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
                samples.append(Float(s) / 32768)
            }
        }
        guard isPlaying else { return }
        if rawFrame >= scheduledEnd {
            // Wiedergabe hat den Puffer eingeholt: erst wieder Vorrat sammeln, dann einmal sauber neu starten.
            if samples.count - scheduledEnd >= Self.startBuffer { try? play(from: scheduledEnd) }
        } else {
            schedule(upTo: samples.count)
        }
    }

    func finish() {
        receivedAll = true
        // Wartete die Wiedergabe gerade auf Vorrat, den Rest jetzt abspielen.
        if isPlaying && rawFrame >= scheduledEnd && scheduledEnd < samples.count {
            try? play(from: scheduledEnd)
        }
    }

    func play(from frame: Int) throws {
        if !engine.isRunning { try engine.start() }
        node.stop()
        segmentStart = min(max(frame, 0), samples.count)
        scheduledEnd = segmentStart
        schedule(upTo: samples.count)
        node.play()
        isPlaying = true
    }

    func pause() {
        pausedFrame = currentFrame
        node.stop()
        isPlaying = false
    }

    func seekPaused(to frame: Int) {
        pausedFrame = min(max(frame, 0), samples.count)
    }

    private func schedule(upTo end: Int) {
        let count = end - scheduledEnd
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress! + scheduledEnd, count: count)
        }
        node.scheduleBuffer(buffer)
        scheduledEnd = end
    }
}
