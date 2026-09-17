import SwiftUI

struct IngredientPickerView: View {
    let catalog: RecipeCatalog
    @Binding var selection: Set<String>
    @State private var query = ""
    @State private var categoryID: String?
    @State private var page = 0
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var matches: [Food] { catalog.searchFoods(query, categoryID: categoryID) }
    private var pageCount: Int { max(1, (matches.count + 5) / 6) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ingredients you avoid").font(Theme.serif(28))
                TextField("Search ingredients or categories", text: $query)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    .focused($searching).submitLabel(.done).onSubmit { searching = false }
                HStack {
                    Menu {
                        Button("All ingredients") { categoryID = nil }
                        ForEach(catalog.categories) { category in
                            Button(catalog.categoryPath(category.id).map(\.name).joined(separator: " › ")) { categoryID = category.id }
                        }
                    } label: { Label(catalog.categories.first { $0.id == categoryID }?.name ?? "All categories", systemImage: "line.3.horizontal.decrease") }
                    Spacer()
                    Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 44)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(Array(matches.dropFirst(page * 6).prefix(6))) { food in
                            Button {
                                if selection.contains(food.id) { selection.remove(food.id) } else { selection.insert(food.id) }
                            } label: {
                                HStack(spacing: 8) {
                                    IngredientArtwork(food: food, symbol: catalog.categoryPath(food.categoryID).last?.symbol ?? "leaf", size: 36)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(food.name).font(.subheadline).multilineTextAlignment(.leading)
                                        Image(systemName: selection.contains(food.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.green)
                                    }
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, minHeight: 64).padding(10)
                                    .background(selection.contains(food.id) ? Theme.sage : .white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).accessibilityLabel(food.name)
                                .accessibilityValue(selection.contains(food.id) ? "Avoid" : "No preference")
                        }
                    }
                    if matches.isEmpty { Text("No matching ingredients yet.").foregroundStyle(.secondary).padding(.vertical) }
                }.scrollBounceBehavior(.basedOnSize)
                HStack {
                    Button("Previous") { page -= 1 }.disabled(page == 0)
                    Spacer()
                    Text("\(page + 1) / \(pageCount)").font(.caption.monospacedDigit())
                    Spacer()
                    Button("Next") { page += 1 }.disabled(page + 1 >= pageCount)
                }.frame(minHeight: 44)
                Button("Done") { dismiss() }.buttonStyle(FilledButton())
            }.padding(24).background(Theme.cream).foregroundStyle(Theme.ink)
                .navigationTitle("Ingredient library").navigationBarTitleDisplayMode(.inline)
                .onChange(of: query) { _, _ in page = 0 }
                .onChange(of: categoryID) { _, _ in page = 0 }
        }
    }
}
