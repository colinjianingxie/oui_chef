import XCTest
@testable import OuiChefCore

final class VoiceRequestTests: XCTestCase {
    func testStaleVoiceActionsAndSameTurnConfirmationsAreRejected() throws {
        let recipe = try XCTUnwrap(RecipeCatalog.bundled().recipes.first)
        var session = try CookingSession(recipe: recipe)
        let request = VoiceRequest(operation: .start_node, sessionID: session.id.uuidString, revision: 0, target: recipe.nodes[0].id, confirmed: true)
        XCTAssertNoThrow(try request.validate(session: session))
        session.pause(true, at: Date())
        XCTAssertThrowsError(try request.validate(session: session))
        let unconfirmed = VoiceRequest(operation: .confirm_labels, sessionID: session.id.uuidString, revision: session.revision)
        XCTAssertThrowsError(try unconfirmed.validate(session: session))
        for operation: VoiceRequest.Operation in [.confirm_ingredient, .confirm_tool, .confirm_labels] {
            let manualOnly = VoiceRequest(operation: operation, sessionID: session.id.uuidString, revision: session.revision, target: "anything", confirmed: true)
            XCTAssertThrowsError(try manualOnly.validate(session: session))
        }
        let confirmation = VoiceConfirmation(target: "proposal", userTurn: 3)
        XCTAssertThrowsError(try confirmation.validate(target: "proposal", userTurn: 3))
        XCTAssertThrowsError(try confirmation.validate(target: "other", userTurn: 4))
        XCTAssertNoThrow(try confirmation.validate(target: "proposal", userTurn: 4))
        XCTAssertThrowsError(try JSONDecoder().decode(VoiceRequest.self, from: Data("{\"operation\":\"delete_database\",\"sessionID\":\"none\",\"revision\":0}".utf8)))
    }
}
