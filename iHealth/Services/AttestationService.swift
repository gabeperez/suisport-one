import Foundation
import DeviceCheck
import CryptoKit

/// App Attest wrapper. Generates (and persists) one hardware-rooted key per install,
/// then signs each workout submission's canonical-hash + server challenge.
///
/// In development the Attest service may be unavailable (simulator). In that case
/// we degrade to an unsigned mode; the backend should refuse to sponsor or mint
/// rewards against unsigned submissions in production.
@MainActor
final class AttestationService {
    static let shared = AttestationService()

    private let service = DCAppAttestService.shared
    private let keyIdDefaultsKey = "SuiSport.AppAttest.KeyID"

    var isAvailable: Bool { service.isSupported }

    /// Returns the attestation key id, generating + attesting on first call.
    /// Caller is responsible for sending the attestation blob to the backend
    /// the first time so the backend can verify the chain against Apple's root CA.
    func getOrCreateKeyID() async throws -> String {
        if let existing = UserDefaults.standard.string(forKey: keyIdDefaultsKey) {
            return existing
        }
        let keyId = try await service.generateKey()
        UserDefaults.standard.set(keyId, forKey: keyIdDefaultsKey)
        return keyId
    }

    /// Sign a canonical payload. Backend produces `challenge`; we hash payload+challenge
    /// and let the Secure Enclave produce an assertion. Backend verifies counter + sig.
    func assert(payload: Data, serverChallenge: Data) async throws -> (keyId: String, assertion: Data) {
        let keyId = try await getOrCreateKeyID()
        let clientData = SHA256.hash(data: payload + serverChallenge)
        let assertion = try await service.generateAssertion(keyId,
                                                            clientDataHash: Data(clientData))
        return (keyId, assertion)
    }
}
