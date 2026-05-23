import Foundation
import AuthenticationServices
import SwiftUI

/// Manages user authentication with Apple Sign In + Supabase
class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var userId: String?
    @Published var isLoading = false
    @Published var error: String?

    private override init() {
        super.init()
        // Check for existing session
        if SupabaseClient.shared.isAuthenticated {
            restoreSession()
        }
    }

    // MARK: - Apple Sign In

    func signInWithApple() {
        isLoading = true
        error = nil

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    func signOut() {
        SupabaseClient.shared.clearSession()
        isAuthenticated = false
        userEmail = nil
        userId = nil
        KeychainManager.shared.setSecureString(nil, forKey: "auth.userEmail")
        KeychainManager.shared.setSecureString(nil, forKey: "auth.userId")
        // Clean up legacy UserDefaults storage (pre-v1.3.1 stored PII here)
        UserDefaults.standard.removeObject(forKey: "auth.userEmail")
        UserDefaults.standard.removeObject(forKey: "auth.userId")
        Log.auth.info("Signed out")
    }

    // MARK: - Session

    private func restoreSession() {
        // Read from Keychain first (v1.3.1+). One-shot migrate any legacy
        // UserDefaults values then wipe them.
        migrateLegacyAuthStorageIfNeeded()
        userEmail = KeychainManager.shared.secureString(forKey: "auth.userEmail")
        userId = KeychainManager.shared.secureString(forKey: "auth.userId")
        isAuthenticated = true
        let email = userEmail ?? "unknown"
        Log.auth.info("Session restored for: \(email, privacy: .private)")
    }

    private func migrateLegacyAuthStorageIfNeeded() {
        let defaults = UserDefaults.standard
        if let legacyEmail = defaults.string(forKey: "auth.userEmail") {
            KeychainManager.shared.setSecureString(legacyEmail, forKey: "auth.userEmail")
            defaults.removeObject(forKey: "auth.userEmail")
        }
        if let legacyId = defaults.string(forKey: "auth.userId") {
            KeychainManager.shared.setSecureString(legacyId, forKey: "auth.userId")
            defaults.removeObject(forKey: "auth.userId")
        }
    }

    private func handleSignIn(idToken: String, email: String?) {
        Task {
            do {
                // Exchange Apple ID token for Supabase session
                let (data, _) = try await SupabaseClient.shared.request(
                    path: "/auth/v1/token?grant_type=id_token",
                    method: "POST",
                    body: [
                        "provider": "apple",
                        "id_token": idToken
                    ]
                )

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["access_token"] as? String,
                   let user = json["user"] as? [String: Any] {

                    let uid = user["id"] as? String
                    let userEmail = email ?? (user["email"] as? String)

                    await MainActor.run {
                        SupabaseClient.shared.setSession(accessToken: accessToken)
                        self.isAuthenticated = true
                        self.userId = uid
                        self.userEmail = userEmail
                        self.isLoading = false

                        KeychainManager.shared.setSecureString(userEmail, forKey: "auth.userEmail")
                        KeychainManager.shared.setSecureString(uid, forKey: "auth.userId")

                        Log.auth.info("Signed in: \(userEmail ?? "unknown", privacy: .private)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                    Log.auth.error("Sign in error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = credential.identityToken,
              let idToken = String(data: identityToken, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.error = "Failed to get Apple ID token"
                self.isLoading = false
            }
            return
        }

        let email = credential.email
        handleSignIn(idToken: idToken, email: email)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async {
            if (error as? ASAuthorizationError)?.code == .canceled {
                self.isLoading = false
            } else {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Sign In View

struct SignInWithAppleButton: View {
    @ObservedObject private var authManager = AuthManager.shared

    var body: some View {
        VStack(spacing: 16) {
            if authManager.isAuthenticated {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed In")
                            .fontWeight(.medium)
                        if let email = authManager.userEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Sign Out") {
                        authManager.signOut()
                    }
                    .controlSize(.small)
                }
            } else {
                if authManager.isLoading {
                    ProgressView("Signing in...")
                } else {
                    SignInWithAppleButtonRepresentable()
                        .frame(height: 44)
                        .onTapGesture {
                            authManager.signInWithApple()
                        }

                    if let error = authManager.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

// MARK: - NSViewRepresentable for Sign In with Apple

struct SignInWithAppleButtonRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> ASAuthorizationAppleIDButton {
        ASAuthorizationAppleIDButton(type: .signIn, style: .white)
    }

    func updateNSView(_ nsView: ASAuthorizationAppleIDButton, context: Context) {}
}
