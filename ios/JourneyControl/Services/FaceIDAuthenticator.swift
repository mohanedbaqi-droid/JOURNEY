import Combine
import Foundation
import LocalAuthentication

@MainActor
final class FaceIDAuthenticator: ObservableObject {
    @Published private(set) var lastError: String?

    /// Enrollment/review of vehicle owner keys requires Face ID, not a passcode fallback.
    func authenticateFaceID(reason: String) async -> Bool {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError),
              context.biometryType == .faceID else {
            lastError = JL("مطلوب Face ID لإدارة أجهزة المالك", "Face ID is required to manage owner devices")
            return false
        }
        do {
            let accepted = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            lastError = accepted ? nil : JL("لم تتم المصادقة", "Face ID not confirmed")
            return accepted
        } catch {
            lastError = JL("فشل Face ID، لم يتم إرسال الموافقة", "Face ID failed; approval not sent")
            return false
        }
    }

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
