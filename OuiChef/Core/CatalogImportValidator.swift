import Foundation

public enum CatalogImportValidator {
    public static func validate(_ data: Data) throws {
        let catalog = try JSONDecoder().decode(RecipeCatalog.self, from: data)
        try IngredientLibrary(schemaVersion: catalog.schemaVersion, categories: catalog.categories, foods: catalog.foods).validate()
        try catalog.validate()
    }
}
