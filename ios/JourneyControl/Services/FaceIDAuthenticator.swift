import Combine
import Foundation
import LocalAuthentication

@MainActor
final class FaceIDAuthenticator: ObservableObject {
    @Published private(set) var lastError: String?

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            lastError = "فعّل Face ID من إعدادات iPhone أولاً."
            return false
        }

        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            lastError = nil
            return true
        } catch {
            lastError = "لم يتم تأكيد Face ID، لذلك لم يُرسل أي أمر إلى السيارة."
            return false
        }
    }
}
