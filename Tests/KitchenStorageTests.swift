import XCTest
@testable import OuiChefCore

final class KitchenStorageTests: XCTestCase {
    func testAccountIsolationGuestAdoptionAndCorruptArchivePreservation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = KitchenStorage(folder: folder)
        let catalog = try RecipeCatalog.bundled()
        var guest = AppArchive()
        guest.preferences.onboardingComplete = true
        guest.savedRecipes = ["bread"]
        try storage.save(guest, accountID: nil)
        XCTAssertEqual(try storage.load(accountID: "alice", adoptingGuest: true, catalog: catalog).savedRecipes, ["bread"])
        XCTAssertTrue(try storage.load(accountID: nil, catalog: catalog).savedRecipes.isEmpty)
        XCTAssertTrue(try storage.load(accountID: "bob", adoptingGuest: true, catalog: catalog).savedRecipes.isEmpty)
        guest.savedRecipes = ["margarita"]
        try storage.save(guest, accountID: nil)
        XCTAssertEqual(try storage.load(accountID: "alice", adoptingGuest: true, catalog: catalog).savedRecipes, ["bread"])
        XCTAssertEqual(try storage.load(accountID: nil, catalog: catalog).savedRecipes, ["margarita"])
        XCTAssertEqual(storage.file(accountID: "../../alice").deletingLastPathComponent().path, folder.path)
        try storage.delete(accountID: "alice")
        XCTAssertTrue(try storage.load(accountID: "alice", catalog: catalog).savedRecipes.isEmpty)
        let corrupt = Data("broken kitchen".utf8)
        try corrupt.write(to: storage.file(accountID: nil))
        XCTAssertThrowsError(try storage.load(accountID: "bob", adoptingGuest: true, catalog: catalog))
        XCTAssertEqual(try Data(contentsOf: storage.file(accountID: nil)), corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.file(accountID: "bob").path))
    }
}
