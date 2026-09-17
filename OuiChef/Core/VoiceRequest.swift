import Foundation

struct VoiceRequest: Codable {
    enum Operation: String, Codable {
        case state, select_recipe, confirm_ingredient, confirm_tool, confirm_labels
        case start_node, ask_readiness, complete_node, recheck, pause, resume
        case propose_ratio, confirm_ratio, set_guidance, mute
    }
    var operation: Operation
    var sessionID: String
    var revision: Int
    var target: String?
    var value: Double?
    var confirmed: Bool?

    func validate(session: CookingSession?) throws {
        if operation == .state || operation == .mute { return }
        guard ![.confirm_ingredient, .confirm_tool, .confirm_labels].contains(operation) else {
            throw CookingError.invalid("Ingredient, equipment, and label checks are manual. Ask the user to finish the checklist on screen before cooking.")
        }
        guard sessionID == (session?.id.uuidString ?? "none"), revision == (session?.revision ?? 0) else {
            throw CookingError.invalid("Cooking state changed. Read the current state and ask again if needed.")
        }
        if ![.state, .ask_readiness, .propose_ratio].contains(operation), confirmed != true {
            throw CookingError.invalid("Ask the user to confirm this action first.")
        }
        if let value, !value.isFinite { throw CookingError.invalid("Invalid quantity.") }
    }

    func requiredTarget() throws -> String {
        guard let target, !target.isEmpty, target.count <= 150 else { throw CookingError.invalid("Choose a specific ingredient, tool, task, or recipe.") }
        return target
    }
}

// A model cannot propose and confirm in the same turn, even if it emits both calls.
struct VoiceConfirmation {
    var target: String
    var userTurn: Int
    func validate(target: String, userTurn: Int) throws {
        guard self.target == target, userTurn > self.userTurn else {
            throw CookingError.invalid("Read the pending question or exact adjustment to the user and wait for their answer.")
        }
    }
}
