import Foundation

enum PublicationStatus: String, Codable { case draft, published }

struct ChefProfile: Codable, Identifiable {
    var id: String
    var name: String
    var bio: String
    var ownerUID: String
    var status: PublicationStatus
}

struct RecipeSetPrice: Codable, Equatable {
    enum Kind: String, Codable { case free, subscription }
    var kind: Kind
    var amountMinor: Int
    var currency: String
    var interval: String?
    var productID: String?

    var label: String {
        if kind == .free { return "Free" }
        // StoreKit's localized price will be authoritative when purchases are enabled.
        return (Double(amountMinor) / 100).formatted(.currency(code: currency)) + (interval == "year" ? " / year" : " / month")
    }
    func validate() throws {
        guard currency == "USD", amountMinor >= 0,
              (kind == .free ? amountMinor == 0 : amountMinor > 0 && ["month", "year"].contains(interval ?? "")) else {
            throw CookingError.invalid("Invalid recipe-set pricing.")
        }
    }
}

struct RecipeSet: Codable, Identifiable {
    var id: String
    var chefID: String
    var chefName: String
    var title: String
    var summary: String
    var status: PublicationStatus
    var classificationIDs: [String]
    var price: RecipeSetPrice
}

struct RecipeSummary: Codable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var style: ChefStyle
    var minutes: String
    var chefID: String
    var chefName: String
    var recipeSetID: String
    var status: PublicationStatus
    var classificationIDs: [String]
    var publishedVersion: Int?
    var hasDraft: Bool
    var baseServings: Int
    var maximumServings: Int
}

struct RecipeClassification: Codable, Identifiable {
    var id: String
    var name: String
    var kind: String
    var parentID: String?
    var appliesTo: [String]
}

extension RecipeSummary {
    init(_ recipe: Recipe) {
        id = recipe.id; title = recipe.title; subtitle = recipe.subtitle; style = recipe.style
        minutes = recipe.minutes; baseServings = recipe.baseServings; maximumServings = recipe.maximumServings
        chefID = recipe.chefID ?? "chef_margarita"; chefName = recipe.chefName ?? "Chef Margarita"
        recipeSetID = recipe.recipeSetID ?? "kitchen_essentials"
        status = .published; classificationIDs = recipe.tags.map { $0.lowercased() }; publishedVersion = recipe.version; hasDraft = false
    }
}
