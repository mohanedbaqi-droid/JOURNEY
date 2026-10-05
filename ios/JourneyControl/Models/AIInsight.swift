import Foundation

struct AIInsight: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case info = 0
        case attention = 1
        case critical = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var title: String {
            switch self {
            case .info: return JL("معلومة", "Information")
            case .attention: return JL("يحتاج انتباه", "Needs attention")
            case .critical: return JL("تحذير", "Warning")
            }
        }

        var symbol: String {
            switch self {
            case .info: return "sparkles"
            case .attention: return "exclamationmark.triangle.fill"
            case .critical: return "exclamationmark.octagon.fill"
            }
        }
    }

    let id: String
    let severity: Severity
    let title: String
    let explanation: String
    let nextStep: String
}
