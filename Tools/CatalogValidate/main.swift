import Foundation
import OuiChefCore

// Uses the same validator as the iOS cooking engine.
do {
    guard CommandLine.arguments.count == 2 else { throw NSError(domain: "Usage: catalog-validate catalog.json", code: 1) }
    try CatalogImportValidator.validate(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    print("Recipe graphs and ingredient library validated.")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
