import Foundation

/// Fragt das API-Guthaben bei Fish Audio ab (GET /wallet/self/api-credit).
/// Dient gleichzeitig als Prüfung, ob der API-Key gültig ist.
@MainActor
final class Balance: ObservableObject {
    static let shared = Balance()

    enum State: Equatable {
        case unknown          // kein Key eingetragen
        case loading
        case value(Decimal)   // Key gültig
        case invalidKey       // Key abgelehnt (401/403)
        case error(String)    // Netz- oder Serverfehler
    }

    @Published private(set) var state: State = .unknown
    private var task: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var lastKey = ""

    private init() {}

    /// Kurz verzögert neu laden – z. B. während der API-Key getippt wird.
    func refreshSoon() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        let key = Settings.shared.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        guard !key.isEmpty else { state = .unknown; lastKey = ""; return }

        // Gleicher Key: alten Wert stehen lassen (kein Flackern). Neuer Key: als „wird geprüft“ zeigen.
        if key != lastKey { state = .loading } else if case .value = state {} else { state = .loading }
        lastKey = key

        var request = URLRequest(url: URL(string: "https://api.fish.audio/wallet/self/api-credit")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        task = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    self?.state = (status == 401 || status == 403) ? .invalidKey : .error("Error \(status)")
                    return
                }
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let raw = json?["credit"]
                let text = (raw as? String) ?? (raw as? NSNumber)?.stringValue
                guard let text, let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                    self?.state = .error("Unexpected response")
                    return
                }
                self?.state = .value(value)
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .error("Can't reach Fish Audio")
            }
        }
    }

    static func format(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
