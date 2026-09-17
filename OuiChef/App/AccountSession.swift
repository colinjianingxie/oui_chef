import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
import Security
import UIKit

@MainActor @Observable
final class AccountSession {
    enum Intent { case signIn, link, deleteAccount }
    static let shared = AccountSession()
    private(set) var accountID: String?
    private(set) var identityID: String?
    private(set) var name = "Guest cook"
    private(set) var email = ""
    private(set) var providers: [String] = []
    private(set) var emailVerified = false
    var busy = false
    var error: String?
    var notice: String?
    var onDeleteLocalAccount: ((String) throws -> Void)?
    private var nonce: String?
    private var listener: AuthStateDidChangeListenerHandle?
    private var verificationID: String? {
        get { UserDefaults.standard.string(forKey: "auth.phoneVerificationID") }
        set { UserDefaults.standard.set(newValue, forKey: "auth.phoneVerificationID") }
    }
    var phoneCodeSent: Bool { verificationID != nil }
    var googleConfigured: Bool { FirebaseApp.app()?.options.clientID?.isEmpty == false }
    var appleConfigured: Bool { Bundle.main.object(forInfoDictionaryKey: "OuiChefAppleSignInEnabled") as? Bool == true }

    private init() {
        update(Auth.auth().currentUser)
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.update(user) }
        }
    }
    private func update(_ user: User?) {
        identityID = user?.uid
        providers = user?.providerData.map(\.providerID).sorted() ?? []
        accountID = providers.isEmpty ? nil : user?.uid
        email = user?.email ?? ""
        emailVerified = user?.isEmailVerified == true
        name = user?.displayName ?? user?.email ?? user?.phoneNumber ?? "Guest cook"
    }
    func run(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false; update(Auth.auth().currentUser) }
        do { try await operation() }
        catch {
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain && ns.code == ASAuthorizationError.canceled.rawValue { return }
            if ns.domain == kGIDSignInErrorDomain && ns.code == GIDSignInError.canceled.rawValue { return }
            self.error = ns.code == AuthErrorCode.requiresRecentLogin.rawValue
                ? "Please verify your sign-in again before deleting your account."
                : error.localizedDescription
        }
    }
    func emailSignIn(email: String, password: String, create: Bool, intent: Intent) async {
        await run {
            let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty, !password.isEmpty else { throw CookingError.invalid("Enter your email and password.") }
            if create {
                guard password.count >= 8 else { throw CookingError.invalid("Use at least 8 characters for your password.") }
                if Auth.auth().currentUser?.isAnonymous == true {
                    _ = try await Auth.auth().currentUser!.link(with: EmailAuthProvider.credential(withEmail: address, password: password))
                } else {
                    _ = try await Auth.auth().createUser(withEmail: address, password: password)
                }
                await migrateVoiceAccess()
                try await Auth.auth().currentUser?.sendEmailVerification()
                notice = "Account created. Check your email to verify your address."
            } else {
                try await finish(EmailAuthProvider.credential(withEmail: address, password: password), intent: intent)
            }
        }
    }
    func resetPassword(email: String) async {
        await run {
            let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { throw CookingError.invalid("Enter your email first.") }
            try await Auth.auth().sendPasswordReset(withEmail: address)
            notice = "If that address has an account, a password reset email is on its way."
        }
    }
    func verifyEmail() async {
        await run {
            try await Auth.auth().currentUser?.sendEmailVerification()
            notice = "Check your email for a verification link."
        }
    }
    func google(intent: Intent) async {
        await run {
            guard let clientID = FirebaseApp.app()?.options.clientID else { throw CookingError.invalid("Google sign-in is still being configured.") }
            guard let presenter = Self.presenter else { throw CookingError.invalid("Please try signing in again.") }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString else { throw CookingError.invalid("Google did not return a sign-in token.") }
            try await finish(GoogleAuthProvider.credential(withIDToken: token, accessToken: result.user.accessToken.tokenString), intent: intent)
        }
    }
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        nonce = nil; error = nil
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            error = "Could not start secure Apple sign-in. Please try again."; return
        }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        nonce = value
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func completeApple(_ result: Result<ASAuthorization, Error>, intent: Intent) async {
        await run {
            defer { nonce = nil }
            let authorization = try result.get()
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce, let data = apple.identityToken, let token = String(data: data, encoding: .utf8) else {
                throw CookingError.invalid("Apple sign-in could not be verified. Please try again.")
            }
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
            let code = apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            try await finish(credential, intent: intent, appleCode: code)
        }
    }
    func sendPhoneCode(_ phone: String) async {
        await run {
            let number = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            guard number.range(of: #"^\+[1-9][0-9]{7,14}$"#, options: .regularExpression) != nil else {
                throw CookingError.invalid("Use a phone number with its country code, such as +1 followed by your number.")
            }
            verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(number, uiDelegate: nil)
            notice = "Enter the verification code sent to your phone."
        }
    }
    func confirmPhoneCode(_ code: String, intent: Intent) async {
        await run {
            guard let verificationID else { throw CookingError.invalid("Request a new verification code first.") }
            guard code.count == 6, code.allSatisfy(\.isNumber) else { throw CookingError.invalid("Enter the six-digit code.") }
            let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)
            try await finish(credential, intent: intent)
            self.verificationID = nil
        }
    }
    func resetPhoneCode() { verificationID = nil; notice = nil }

    private func finish(_ credential: AuthCredential, intent: Intent, appleCode: String? = nil) async throws {
        switch intent {
        case .link:
            guard let user = Auth.auth().currentUser, !user.isAnonymous else { throw CookingError.invalid("Sign in before adding another sign-in method.") }
            _ = try await user.link(with: credential)
            if credential.provider == "password" { try await user.sendEmailVerification() }
            notice = "Sign-in method added to this account."
        case .deleteAccount:
            guard let user = Auth.auth().currentUser else { throw CookingError.invalid("Sign in before deleting your account.") }
            let uid = user.uid
            _ = try await user.reauthenticate(with: credential)
            if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
                guard let appleCode else { throw CookingError.invalid("Use Apple to confirm deletion of this account.") }
                try await Auth.auth().revokeToken(withAuthorizationCode: appleCode)
            }
            try await user.delete()
            try onDeleteLocalAccount?(uid)
            GIDSignIn.sharedInstance.signOut()
            notice = "Your account and its kitchen on this iPhone were deleted."
        case .signIn:
            if let guest = Auth.auth().currentUser, guest.isAnonymous {
                do { _ = try await guest.link(with: credential) }
                catch {
                    let ns = error as NSError
                    guard ns.code == AuthErrorCode.credentialAlreadyInUse.rawValue else { throw error }
                    let updated = ns.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential ?? credential
                    _ = try await Auth.auth().signIn(with: updated)
                }
            } else { _ = try await Auth.auth().signIn(with: credential) }
            await migrateVoiceAccess()
        }
    }
    private func migrateVoiceAccess() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--auth-emulator") { return }
        #endif
        let legacy = CloudVoiceAccount()
        guard legacy.hasLegacyIdentity, let user = Auth.auth().currentUser else { return }
        do {
            let oldToken = try await legacy.legacyIDToken()
            guard let endpoint = CloudVoiceAccount.endpoint,
                  var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            url.scheme = "https"; url.path = "/account/claim-voice"
            var request = URLRequest(url: url.url!)
            request.httpMethod = "POST"; request.timeoutInterval = 20
            request.setValue("Bearer \(try await user.getIDToken(forcingRefresh: true))", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["legacyToken": oldToken])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CookingError.invalid("Voice access transfer is pending.") }
            try legacy.clearLegacyIdentity()
        } catch { notice = "You're signed in. Development voice access may still need enrollment; your account ID is in Profile." }
    }
    func signOut() async {
        await run {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            verificationID = nil
        }
    }
    static var presenter: UIViewController? {
        var controller = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
