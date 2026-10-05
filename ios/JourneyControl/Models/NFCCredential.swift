import Foundation

enum NFCCredentialKind: String, Codable, CaseIterable, Identifiable {
    case physicalCard
    case androidPhone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .physicalCard: return JL("بطاقة أو ميدالية", "Card or key fob")
        case .androidPhone: return JL("هاتف أندرويد HCE", "Android HCE phone")
        }
    }

    var symbol: String {
        switch self {
        case .physicalCard: return "creditcard.fill"
        case .androidPhone: return "iphone"
        }
    }
}

struct NFCCredential: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var kind: NFCCredentialKind
    var identifier: String
    var isEnabled: Bool
    var allowsRemoteStart: Bool
    var isBenchCredential: Bool
    let createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        kind: NFCCredentialKind,
        identifier: String,
        isEnabled: Bool = true,
        allowsRemoteStart: Bool = true,
        isBenchCredential: Bool = true,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.identifier = identifier
        self.isEnabled = isEnabled
        self.allowsRemoteStart = allowsRemoteStart
        self.isBenchCredential = isBenchCredential
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    var maskedIdentifier: String {
        let clean = identifier.replacingOccurrences(of: " ", with: "")
        guard clean.count > 6 else { return clean }
        return "•••• " + clean.suffix(6)
    }
}

struct NFCAccessSettings: Codable, Equatable {
    var repeatGuardSeconds = 5
    var iphoneRequiresFaceID = true
    var iphoneActionTitle = JL("فتح + تشغيل عن بُعد", "Unlock + Remote start")
}

struct NFCAccessEvent: Identifiable, Codable, Equatable {
    enum Result: String, Codable {
        case allowed
        case denied
        case bench
    }

    let id: UUID
    let timestamp: Date
    let title: String
    let detail: String
    let result: Result

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        title: String,
        detail: String,
        result: Result
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.result = result
    }
}
