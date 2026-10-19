import Foundation
import Combine
import Security

/// Opt-in history API. Never embeds a server token in the app binary.
@MainActor final class JourneyHistoryAPI: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var stops: [Stop] = []
    @Published var stats: Stats?
    @Published var error: String?
    @Published var loading = false

    struct Trip: Codable, Identifiable {
        let id: Int64
        let started_at: Date
        let ended_at: Date?
        let distance_m: Double
        let max_speed_kph: Double
        let start_lat: Double
        let start_lon: Double
    }
    struct Stop: Codable, Identifiable {
        let id: Int64
        let arrived_at: Date
        let departed_at: Date?
        let lat: Double
        let lon: Double
    }
    struct Stats: Codable {
        let trip_count: Int
        let distance_m: Double
        let max_speed_kph: Double
    }
    struct Point: Codable {
        let recorded_at: Date
        let lat: Double
        let lon: Double
        let speed_kph: Double?
        let heading: Double?
    }
    @Published var selectedTripPoints: [Point] = []
    @Published var baseURL = UserDefaults.standard.string(forKey: "journey.history.url") ?? ""
    @Published var token = ""
    private let keychainService = "com.abuseif.journey.history"
    init() { token = readToken() }

    private func readToken() -> String {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:keychainService, kSecAttrAccount as String:"api-token",
            kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return "" }
        return String(data:data,encoding:.utf8) ?? ""
    }
    func saveConfiguration() {
        baseURL = baseURL.trimmingCharacters(in:.whitespacesAndNewlines)
        token = token.trimmingCharacters(in:.whitespacesAndNewlines)
        UserDefaults.standard.set(baseURL,forKey:"journey.history.url")
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:keychainService,kSecAttrAccount as String:"api-token"]
        SecItemDelete(q as CFDictionary)
        if !token.isEmpty {
            var entry=q
            entry[kSecValueData as String]=Data(token.utf8)
            entry[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(entry as CFDictionary,nil)
        }
    }
    private func fetch<T: Decodable>(_ path: String) async throws -> T {
        guard let base=URL(string:baseURL),base.scheme=="https",base.host != nil,
              let url=URL(string:path,relativeTo:base)?.absoluteURL,
              url.host==base.host, !token.isEmpty else {
            throw URLError(.badURL)
        }
        var req=URLRequest(url:url)
        req.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        req.timeoutInterval=20
        let (data,response)=try await URLSession.shared.data(for:req)
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else {
            throw URLError(.badServerResponse)
        }
        let decoder=JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp")
        }
        return try decoder.decode(T.self,from:data)
    }
    func refresh() async {
        guard !loading else { return }
        loading=true
        defer {loading=false}
        do {
            async let t: [Trip] = fetch("/api/trips")
            async let s: [Stop] = fetch("/api/stops")
            async let x: Stats = fetch("/api/stats")
            let (tr,st,stat)=try await (t,s,x)
            trips=tr;stops=st;stats=stat;error=nil
        } catch { self.error=error.localizedDescription }
    }
    func loadPoints(tripID: Int64) async {
        do { selectedTripPoints = try await fetch("/api/trips/\(tripID)/points") }
        catch { self.error=error.localizedDescription }
    }
}
