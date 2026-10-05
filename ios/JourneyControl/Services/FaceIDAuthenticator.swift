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
            lastError = JL("فعّل Face ID من إعدادات iPhone أولاً.", "Enable Face ID in iPhone settings first.")
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
            lastError = JL("لم يتم تأكيد Face ID، لذلك لم يُرسل أي أمر إلى السيارة.", "Face ID was not confirmed. No vehicle command was sent.")
            return false
        }
    }
}
