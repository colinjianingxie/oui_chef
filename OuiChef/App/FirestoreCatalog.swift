import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class FirestoreCatalog {
    let db = Firestore.firestore()

    func isAdmin() async throws -> Bool {
        guard let user = Auth.auth().currentUser, user.isEmailVerified, let email = user.email?.lowercased() else { return false }
        return try await db.document("catalogAdmins/\(email)").getDocument(source: .server).data()?["enabled"] as? Bool == true
    }

    func cards(search: String = "", classification: String? = nil, setID: String? = nil,
               drafts: Bool = false, after: DocumentSnapshot? = nil) async throws -> ([RecipeSummary], DocumentSnapshot?) {
        var query: Query = drafts ? db.collection("recipes").whereField("hasDraft", isEqualTo: true) : db.collection("recipes").whereField("status", isEqualTo: "published")
        if !search.isEmpty { query = query.whereField("searchTokens", arrayContains: search.lowercased().trimmingCharacters(in: .whitespaces)) }
        else if let classification { query = query.whereField("tags", arrayContains: classification) }
        if let setID { query = query.whereField("recipeSetID", isEqualTo: setID) }
        query = query.order(by: "title").limit(to: 12)
        if let after { query = query.start(afterDocument: after) }
        let docs = try await query.getDocuments(source: .server).documents
        return (try docs.map { try $0.data(as: RecipeSummary.self) }, docs.count == 12 ? docs.last : nil)
    }

    func savedCards(_ ids: [String]) async throws -> [RecipeSummary] {
        guard !ids.isEmpty else { return [] }
        return try await db.collection("recipes").whereField("status", isEqualTo: "published")
            .whereField(FieldPath.documentID(), in: ids).getDocuments(source: .server).documents
            .map { try $0.data(as: RecipeSummary.self) }.sorted { $0.title < $1.title }
    }

    func sets(after: DocumentSnapshot? = nil) async throws -> ([RecipeSet], DocumentSnapshot?) {
        var query = db.collection("recipeSets").whereField("status", isEqualTo: "published").order(by: "title").limit(to: 12)
        if let after { query = query.start(afterDocument: after) }
        let docs = try await query.getDocuments(source: .server).documents
        let sets = try docs.map { try $0.data(as: RecipeSet.self) }
        for set in sets {
            if let price = set.price { try price.validate() }
            guard set.access != nil || set.price != nil else { throw CookingError.invalid("Recipe-set access is missing.") }
        }
        return (sets, docs.count == 12 ? docs.last : nil)
    }

    func ingredients(search: String, category: String?, after: DocumentSnapshot?) async throws -> ([Food], DocumentSnapshot?) {
        var query: Query = db.collection("ingredients")
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty { query = query.whereField("searchTokens", arrayContains: term) }
        else if let category { query = query.whereField("categoryAncestors", arrayContains: category) }
        query = query.order(by: "name").limit(to: 6)
        if let after { query = query.start(afterDocument: after) }
        let docs = try await query.getDocuments(source: .server).documents
        return (try docs.map { try $0.data(as: Food.self) }, docs.count == 6 ? docs.last : nil)
    }

    func categories() async throws -> [FoodCategory] {
        try await db.collection("ingredientCategories").getDocuments(source: .server).documents.map { try $0.data(as: FoodCategory.self) }
    }

    func recipe(_ id: String, draft: Bool) async throws -> (Recipe, IngredientLibrary, String?) {
        guard !id.isEmpty, !id.contains("/") else { throw CookingError.invalid("Invalid recipe ID.") }
        let card = try await db.document("recipes/\(id)").getDocument(source: .server).data(as: RecipeSummary.self)
        guard draft || card.publishedVersion != nil else { throw CookingError.invalid("This recipe is not published yet.") }
        let version = draft ? "draft" : String(card.publishedVersion!)
        struct Version: Decodable { var recipe: Recipe; var revision: String? }
        let content = try await db.document("recipes/\(id)/versions/\(version)").getDocument(source: .server).data(as: Version.self)
        let recipe = content.recipe
        guard recipe.id == id, recipe.chefID == card.chefID, recipe.recipeSetID == card.recipeSetID else { throw CookingError.invalid("Recipe references do not match.") }
        let ids = Set(recipe.ingredients.flatMap { [$0.foodID] + ($0.alternatives ?? []).map(\.foodID) })
        let library = try await ingredientLibrary(ids)
        try RecipeCatalog(schemaVersion: 1, foods: library.foods, recipes: [recipe], categories: library.categories).validate()
        return (recipe, library, content.revision)
    }

    func ingredientLibrary(_ ids: Set<String>) async throws -> IngredientLibrary {
        var pending = ids, foods: [String: Food] = [:]
        while !pending.isEmpty {
            let batch = Array(pending.prefix(20))
            guard foods.count + batch.count <= 300, batch.allSatisfy({ !$0.isEmpty && !$0.contains("/") }) else { throw CookingError.invalid("Ingredient tree is too large or invalid.") }
            let docs = try await db.collection("ingredients").whereField(FieldPath.documentID(), in: batch).getDocuments(source: .server).documents
            guard docs.count == batch.count else { throw CookingError.invalid("An ingredient is missing from the library.") }
            for doc in docs {
                let food = try doc.data(as: Food.self)
                guard food.id == doc.documentID else { throw CookingError.invalid("Ingredient ID mismatch.") }
                foods[food.id] = food
                pending.formUnion(food.constituents)
            }
            pending.subtract(foods.keys)
        }
        let library = IngredientLibrary(schemaVersion: 1, categories: try await categories(), foods: Array(foods.values))
        try library.validate()
        return library
    }

    func publish(_ id: String, draftRevision: String) async throws {
        guard let user = Auth.auth().currentUser else { throw CookingError.invalid("Sign in to publish.") }
        let token = try await user.getIDToken()
        guard let endpoint = CloudVoiceAccount.endpoint, var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw CookingError.invalid("Catalog service is unavailable.") }
        url.scheme = "https"; url.path = "/catalog/publish"
        var request = URLRequest(url: url.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["recipeID": id, "draftRevision": draftRevision])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
            throw CookingError.invalid(detail ?? "Publishing failed. Refresh the draft and try again.")
        }
    }
}
