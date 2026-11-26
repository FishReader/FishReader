import Foundation
import AppKit

/// Holt Audio per Streaming von Fish Audio, puffert es und steuert die Wiedergabe.
@MainActor
final class Speaker: ObservableObject {
    static let shared = Speaker()

    enum Phase: Equatable {
        case idle, loading, playing, paused, finished
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var receiving = false

    var isBusy: Bool { phase == .loading || phase == .playing }
    var hasTrack: Bool { player.frameCount > 0 }
    var progress: Double { duration > 0 ? min(1, position / duration) : 0 }

    private let player = StreamPlayer()
    private var task: Task<Void, Never>?
    private var generation = 0
    private var ticker: Timer?

    private init() {
        player.onLevel = { [weak self] level in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Nur spürbare Änderungen veröffentlichen, sonst zeichnet die UI ständig neu.
                let value = self.phase == .playing ? level : 0
                if abs(value - self.level) > 0.04 || (value == 0 && self.level != 0) { self.level = value }
            }
        }
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let pos = Double(player.currentFrame) / StreamPlayer.sampleRate
        let dur = Double(player.frameCount) / StreamPlayer.sampleRate
        if abs(pos - position) > 0.04 { position = pos }
        if dur != duration { duration = dur }
        if phase == .playing && player.isAtEnd {
            player.pause()
            level = 0
            position = duration
            phase = .finished
        }
    }

    // MARK: Bedienung

    /// Globaler Shortcut: läuft etwas, wird angehalten – sonst die Auswahl vorgelesen.
    func shortcutPressed() {
        if isBusy { halt(); return }
        Task { await speakSelection() }
    }

    /// Runder Play-Knopf im Panel.
    func playButtonPressed() {
        switch phase {
        case .loading: halt()
        case .playing: pause()
        case .paused: resume()
        case .finished: seek(to: 0)
        case .idle, .error: speakClipboard()
        }
    }

    func pause() {
        guard phase == .playing else { return }
        player.pause()
        level = 0
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        if player.isAtEnd { seek(to: 0); return }
        start(from: player.currentFrame)
    }

    func seek(to fraction: Double) {
        guard hasTrack else { return }
        let frame = Int(Double(player.frameCount) * min(max(fraction, 0), 1))
        if phase == .paused {
            player.seekPaused(to: frame)
        } else {
            start(from: frame)
        }
        tick()
    }

    /// Download abbrechen und anhalten; bereits Empfangenes bleibt zum Nachhören erhalten.
    func halt() {
        generation += 1
        task?.cancel()
        task = nil
        receiving = false
        if player.isPlaying { player.pause() }
        if hasTrack { player.finish() }
        level = 0
        phase = hasTrack ? .paused : .idle
    }

    func fail(_ message: String) {
        phase = .error(message)
    }

    private func start(from frame: Int) {
        do {
            try player.play(from: frame)
            phase = .playing
        } catch {
            phase = .error("Audio output failed: \(error.localizedDescription)")
        }
    }

    // MARK: Quellen

    private func speakSelection() async {
        guard SelectionReader.isTrusted else {
            SelectionReader.requestTrust()
            fail("Accessibility access required.")
            return
        }
        guard let text = await SelectionReader.selectedText(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("No selected text found.")
            return
        }
        speak(text)
    }

    func speakClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("Clipboard contains no text.")
            return
        }
        speak(text)
    }

    func speak(_ text: String) {
        halt()
        player.reset()
        position = 0
        duration = 0

        let settings = Settings.shared
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            fail("Add your Fish Audio API key first.")
            return
        }

        phase = .loading
        receiving = true
        let gen = generation

        var body: [String: Any] = [
            "text": text,
            "format": "pcm",
            "sample_rate": Int(StreamPlayer.sampleRate),
            "latency": "balanced",
            "normalize": true,
            "prosody": ["speed": settings.speed],
        ]
        let voice = settings.voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !voice.isEmpty { body["reference_id"] = voice }

        var request = URLRequest(url: URL(string: "https://api.fish.audio/v1/tts")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Settings.model, forHTTPHeaderField: "model")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        task = Task { [weak self] in
            guard let self else { return }
            do {
                var first = true
                for try await var chunk in Self.audioStream(request) {
                    guard gen == self.generation else { return }
                    if first {
                        first = false
                        // Falls doch ein WAV-Header vorangestellt ist: überspringen.
                        if chunk.count >= 44, chunk.starts(with: Array("RIFF".utf8)) { chunk = Data(chunk.dropFirst(44)) }
                    }
                    if chunk.count % 2 == 1 { chunk.removeLast() }   // nur beim allerletzten Stück möglich
                    self.player.append(chunk)
                    // Erst loslegen, wenn ein kleiner Vorrat da ist – sonst stottert es.
                    if self.phase == .loading && self.player.frameCount >= StreamPlayer.startBuffer {
                        self.start(from: 0)
                    }
                }
                guard gen == self.generation else { return }
                self.player.finish()
                self.receiving = false
                if self.phase == .loading {
                    if self.hasTrack { self.start(from: 0) } else { self.fail("No audio received.") }
                }
                Balance.shared.refresh()
            } catch {
                guard gen == self.generation, !(error is CancellationError) else { return }
                self.receiving = false
                if self.hasTrack { self.player.finish() }
                if self.player.isPlaying { self.player.pause() }
                self.level = 0
                self.fail((error as? TTSError)?.message ?? error.localizedDescription)
                if (error as? TTSError)?.status == 402 { Balance.shared.refresh() }
            }
        }
    }

    /// Liest die HTTP-Antwort abseits des Main-Threads und liefert sie in 8-KB-Stücken
    /// (gerade Byte-Anzahl, nur das letzte Stück kann kürzer sein).
    nonisolated private static func audioStream(_ request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await b in bytes where data.count < 2000 { data.append(b) }
                        throw TTSError(status: status, body: String(data: data, encoding: .utf8) ?? "")
                    }
                    var chunk = Data(capacity: 8192)
                    for try await b in bytes {
                        chunk.append(b)
                        if chunk.count >= 8192 {
                            continuation.yield(chunk)
                            chunk = Data(capacity: 8192)
                        }
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct TTSError: Error {
    let status: Int
    let body: String

    var message: String {
        switch status {
        case 401: return "Invalid API key (401)."
        case 402: return "Out of API credits (402). Top up at fish.audio."
        case 429: return "Too many requests (429). Try again shortly."
        case 503: return "Fish Audio is overloaded (503). Try again later."
        default:
            let detail = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["message"] as? String
            return "Error \(status): \(detail ?? String(body.prefix(160)))"
        }
    }
}
