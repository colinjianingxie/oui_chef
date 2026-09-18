import Foundation

struct CompletedDish: Codable, Identifiable, Equatable {
    var id: UUID
    var recipeID: String
    var recipeVersion: Int
    var title: String
    var chefName: String
    var servings: Int
    var completedAt: Date
    var adjustments: [String]
    var photoFile: String?
    var photoPath: String?
    var needsUpload = true
    var deletePhoto: Bool?
    var photoVersion: String?
    var inProgress: Bool?

    init(_ session: CookingSession) {
        id = session.id; recipeID = session.recipe.id; recipeVersion = session.recipe.version
        title = session.recipe.title; chefName = session.recipe.chefName ?? "Chef Margarita"
        servings = session.servings; completedAt = session.completedAt ?? session.createdAt
        adjustments = session.adjustmentSummary
    }
    enum CodingKeys: String, CodingKey {
        case id, recipeID, recipeVersion, title, chefName, servings, completedAt, adjustments
        case photoFile, photoPath, needsUpload, deletePhoto, photoVersion, inProgress
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        recipeID = try c.decode(String.self, forKey: .recipeID)
        recipeVersion = try c.decode(Int.self, forKey: .recipeVersion)
        title = try c.decode(String.self, forKey: .title); chefName = try c.decode(String.self, forKey: .chefName)
        servings = try c.decode(Int.self, forKey: .servings); completedAt = try c.decode(Date.self, forKey: .completedAt)
        adjustments = try c.decode([String].self, forKey: .adjustments)
        photoFile = try c.decodeIfPresent(String.self, forKey: .photoFile)
        photoPath = try c.decodeIfPresent(String.self, forKey: .photoPath)
        photoVersion = try c.decodeIfPresent(String.self, forKey: .photoVersion)
        inProgress = try c.decodeIfPresent(Bool.self, forKey: .inProgress)
        deletePhoto = try c.decodeIfPresent(Bool.self, forKey: .deletePhoto)
        needsUpload = try c.decodeIfPresent(Bool.self, forKey: .needsUpload) ?? false
    }

}

extension AppArchive {
    var dishes: [CompletedDish] { (completedDishes ?? []).filter { $0.inProgress != true }.sorted { $0.completedAt > $1.completedAt } }

    mutating func reconcileCompletion(_ session: CookingSession) {
        if completedDishes == nil { completedDishes = [] }
        if session.finished {
            // A profile entry deleted by the user stays deleted until a new cooking attempt.
            guard !(hiddenDishIDs ?? []).contains(session.id) else { return }
            deletedDishIDs?.remove(session.id)
            if let index = completedDishes?.firstIndex(where: { $0.id == session.id }) {
                guard completedDishes?[index].inProgress == true || completedDishes?[index].adjustments != session.adjustmentSummary else { return }
                completedDishes?[index].inProgress = nil
                completedDishes?[index].completedAt = session.completedAt ?? session.createdAt
                completedDishes?[index].adjustments = session.adjustmentSummary
                completedDishes?[index].needsUpload = true
            } else { completedDishes?.append(CompletedDish(session)) }
        } else if let index = completedDishes?.firstIndex(where: { $0.id == session.id && $0.inProgress != true }) {
            // Keep the local photo if the user corrects a premature completion.
            completedDishes?[index].inProgress = true
            completedDishes?[index].needsUpload = true
            if deletedDishIDs == nil { deletedDishIDs = [] }
            deletedDishIDs?.insert(session.id)
        }
    }
}
