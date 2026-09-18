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

struct RecipeSetAccess: Codable {
    var kind: RecipeSetPrice.Kind
    var productID: String?
}

struct RecipeSet: Codable, Identifiable {
    var id: String
    var chefID: String
    var chefName: String
    var title: String
    var summary: String
    var status: PublicationStatus
    var classificationIDs: [String]? // Legacy wire field, retained while old clients are in use.
    var tags: [String]?
    var discoveryTags: [String] { tags ?? classificationIDs ?? [] }
    var price: RecipeSetPrice?
    var access: RecipeSetAccess?
    var accessLabel: String { access.map { $0.kind == .free ? "Free" : "Subscription" } ?? price?.label ?? "Unavailable" }
}

struct RecipeSummary: Codable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var style: ChefStyle
    var minutes: String
    var totalMinutes: Int?
    var maximumMinutes: Int?
    var timeLabel: String { timeEstimate(totalMinutes, maximumMinutes, fallback: minutes) }
    var chefID: String
    var chefName: String
    var recipeSetID: String
    var status: PublicationStatus
    var classificationIDs: [String]? // Legacy wire field, retained while old clients are in use.
    var tags: [String]?
    var discoveryTags: [String] { tags ?? classificationIDs ?? [] }
    var publishedVersion: Int?
    var hasDraft: Bool
    var baseServings: Int
    var maximumServings: Int
}

struct CatalogTag: Codable, Identifiable {
    var id: String
    var name: String
    static let all: [CatalogTag] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "catalog-tags", withExtension: "json"),
              let data = try? Data(contentsOf: url), let tags = try? JSONDecoder().decode([CatalogTag].self, from: data) else { return [] }
        return tags
    }()
}

extension RecipeSummary {
    init(_ recipe: Recipe) {
        id = recipe.id; title = recipe.title; subtitle = recipe.subtitle; style = recipe.style
        minutes = recipe.minutes; totalMinutes = recipe.totalMinutes; maximumMinutes = recipe.maximumMinutes; baseServings = recipe.baseServings; maximumServings = recipe.maximumServings
        chefID = recipe.chefID ?? "chef_margarita"; chefName = recipe.chefName ?? "Chef Margarita"
        recipeSetID = recipe.recipeSetID ?? "kitchen_essentials"
        tags = recipe.tags.map { $0.lowercased() }; status = .published; classificationIDs = tags; publishedVersion = recipe.version; hasDraft = false
    }
}

func timeEstimate(_ minimum: Int?, _ maximum: Int?, fallback: String) -> String {
    guard let minimum else { return fallback }
    if let maximum, maximum > minimum {
        if minimum % 60 == 0 && maximum % 60 == 0 { return "\(minimum / 60)–\(maximum / 60) hr" }
        return "\(minimum)–\(maximum) min"
    }
    return "\(minimum) min"
}

extension Recipe {
    var timeLabel: String { timeEstimate(totalMinutes, maximumMinutes, fallback: minutes) }
}
