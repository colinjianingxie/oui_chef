import Foundation
import CryptoKit

struct UsageRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var name: String
    var recipeID: String?
}

struct AppArchive: Codable {
    var version = 1
    var preferences = ChefPreferences()
    var session: CookingSession?
    var history: [CookingSession] = []
    var savedRecipes = Set<String>()
    var usage: [UsageRecord] = []
}

struct KitchenStorage {
    var folder = URL.applicationSupportDirectory.appending(path: "OuiChef", directoryHint: .isDirectory)

    func file(accountID: String?) -> URL {
        let name = accountID.map { "account-" + SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() } ?? "kitchen"
        return folder.appendingPathComponent(name + ".json")
    }

    func load(accountID: String?, adoptingGuest: Bool = false, catalog: RecipeCatalog) throws -> AppArchive {
        let target = file(accountID: accountID)
        let guest = file(accountID: nil)
        let source = !FileManager.default.fileExists(atPath: target.path) && adoptingGuest && accountID != nil ? guest : target
        guard FileManager.default.fileExists(atPath: source.path) else { return AppArchive() }
        let archive = try JSONDecoder().decode(AppArchive.self, from: Data(contentsOf: source))
        guard archive.version == 1 else { throw CookingError.invalid("This saved kitchen uses a newer app format.") }
        if let saved = archive.session { try RecipeCatalog(schemaVersion: 1, foods: catalog.foods, recipes: [saved.recipe]).validate() }
        // Move only after validation. A failed read preserves the original, and sign-out cannot reopen adopted data.
        if source != target { try FileManager.default.moveItem(at: source, to: target) }
        return archive
    }

    func save(_ archive: AppArchive, accountID: String?) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: file(accountID: accountID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete(accountID: String) throws {
        let target = file(accountID: accountID)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }
}
