import Foundation
import FirebaseAuth
import Security

@MainActor
final class CloudVoiceAccount {
    struct Identity: Codable { var uid: String; var refreshToken: String }
    var uid: String? { Auth.auth().currentUser?.uid ?? (try? readIdentity())?.uid }
    var hasLegacyIdentity: Bool { (try? readIdentity()) != nil }
    private let service = "com.xie.ouichef.voice-auth"
    private var token: String?
    private var expires = Date.distantPast

    static var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "OuiChefVoiceURL") as? String,
              let url = URL(string: raw), url.scheme == "wss", url.host != nil else { return nil }
        return url
    }
    private var apiKey: String? {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["API_KEY"] as? String
    }
    func idToken() async throws -> String {
        if let user = Auth.auth().currentUser { return try await user.getIDToken(forcingRefresh: false) }
        if hasLegacyIdentity { return try await legacyIDToken() }
        let result = try await Auth.auth().signInAnonymously()
        return try await result.user.getIDToken(forcingRefresh: false)
    }
    // ponytail: retain the old anonymous sign-in only until existing development devices migrate.
    func legacyIDToken() async throws -> String {
        if let token, expires.timeIntervalSinceNow > 60 { return token }
        guard let key = apiKey else { throw CookingError.invalid("Firebase voice configuration is missing.") }
        guard let saved = try readIdentity() else { throw CookingError.invalid("No previous development sign-in is saved.") }
        var components = URLComponents(string: "https://securetoken.googleapis.com/v1/token")!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [.init(name: "grant_type", value: "refresh_token"), .init(name: "refresh_token", value: saved.refreshToken)]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = body["idToken"] as? String ?? body["id_token"] as? String,
              let refresh = body["refreshToken"] as? String ?? body["refresh_token"] as? String,
              let uid = body["localId"] as? String ?? body["user_id"] as? String else {
            throw CookingError.invalid("Voice sign-in is unavailable. Check Firebase's development authentication setup.")
        }
        try saveIdentity(Identity(uid: uid, refreshToken: refresh))
        token = newToken
        expires = Date().addingTimeInterval(3500)
        return newToken
    }
    func clearLegacyIdentity() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "development"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CookingError.invalid("Could not remove the old development sign-in.") }
        token = nil
    }
    private func readIdentity() throws -> Identity? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: "development", kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CookingError.invalid("Could not open the saved voice sign-in.") }
        return try JSONDecoder().decode(Identity.self, from: data)
    }
    private func saveIdentity(_ identity: Identity) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "development"]
        let fields: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(identity), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, fields as CFDictionary)
        let result = status == errSecItemNotFound ? SecItemAdd(query.merging(fields, uniquingKeysWith: { _, new in new }) as CFDictionary, nil) : status
        guard result == errSecSuccess else { throw CookingError.invalid("Could not securely save voice sign-in.") }
    }
}
