import XCTest
@testable import OuiChefCore

final class RecipeShareLinkTests: XCTestCase {
    func testOnlyOurRecipeLinksAreAccepted() {
        let id = "0123456789abcdef0123456789abcdef"
        for link in ["https://\(RecipeShareLink.host)/r/\(id)", "https://\(RecipeShareLink.host)/r/\(id)?from=friend", "ouichef://recipe/\(id)"] {
            XCTAssertEqual(RecipeShareLink.id(from: URL(string: link)!), id)
        }
        for link in ["http://\(RecipeShareLink.host)/r/\(id)", "https://example.com/r/\(id)", "https://\(RecipeShareLink.host).evil.example/r/\(id)", "https://user@\(RecipeShareLink.host)/r/\(id)", "https://\(RecipeShareLink.host):443/r/\(id)", "https://\(RecipeShareLink.host)/r/../\(id)", "https://\(RecipeShareLink.host)/r/\(id)/extra", "https://\(RecipeShareLink.host)/r/short", "ouichef://other/\(id)"] {
            XCTAssertNil(RecipeShareLink.id(from: URL(string: link)!), link)
        }
    }
}
