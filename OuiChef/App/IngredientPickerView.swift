import SwiftUI
import FirebaseFirestore

struct IngredientPickerView: View {
    @Bindable var store: ChefStore
    private var catalog: RecipeCatalog { store.catalog ?? RecipeCatalog(schemaVersion: 1, foods: [], recipes: []) }
    @Binding var selection: Set<String>
    @State private var query = ""
    @State private var categoryID: String?
    @State private var page = 0
    @FocusState private var searching: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var matches: [Food] = []
    @State private var cursors: [DocumentSnapshot?] = [nil]
    @State private var nextCursor: DocumentSnapshot?
    @State private var loading = false
    @State private var notice: String?
    private var requestID: String { "\(query)|\(categoryID ?? "")|\(page)" }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ingredients you avoid").font(Theme.serif(28))
                TextField("Search all ingredients", text: $query)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    .focused($searching).submitLabel(.done).onSubmit { searching = false }
                HStack {
                    Menu {
                        Button("All ingredients") { categoryID = nil; query = "" }
                        ForEach(catalog.categories) { category in
                            Button(catalog.categoryPath(category.id).map(\.name).joined(separator: " › ")) { categoryID = category.id; query = "" }
                        }
                    } label: { Label(catalog.categories.first { $0.id == categoryID }?.name ?? "All categories", systemImage: "line.3.horizontal.decrease") }
                    Spacer()
                    Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 44)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(matches) { food in
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
                    if loading { ProgressView("Loading ingredients…") }
                    if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if matches.isEmpty && !loading { Text("No matching ingredients yet.").foregroundStyle(.secondary).padding(.vertical) }
                }.scrollBounceBehavior(.basedOnSize)
                HStack {
                    Button("Previous") { page -= 1 }.disabled(page == 0 || loading)
                    Spacer()
                    Text("Page \(page + 1)").font(.caption.monospacedDigit())
                    Spacer()
                    Button("Next") { cursors = Array(cursors.prefix(page + 1)) + [nextCursor]; page += 1 }.disabled(nextCursor == nil || loading)
                }.frame(minHeight: 44)
                Button("Done") { dismiss() }.buttonStyle(FilledButton())
            }.padding(24).background(Theme.cream).foregroundStyle(Theme.ink)
                .navigationTitle("Ingredient library").navigationBarTitleDisplayMode(.inline)
                .onChange(of: query) { _, text in page = 0; cursors = [nil]; if !text.isEmpty { categoryID = nil } }
                .onChange(of: categoryID) { _, _ in page = 0; cursors = [nil] }
                .task(id: requestID) { await load() }
        }
    }
    private func load() async {
        let request = requestID
        loading = true; notice = nil; nextCursor = nil
        defer { if requestID == request { loading = false } }
        do {
            try await Task.sleep(for: .milliseconds(250))
            let result = try await store.remoteCatalog.ingredients(search: query, category: categoryID, after: cursors[page])
            guard !Task.isCancelled, requestID == request else { return }
            matches = result.0; nextCursor = result.1
            // Remember visible names for selected preferences without downloading the whole library.
            store.mergeLibrary(IngredientLibrary(schemaVersion: 1, categories: catalog.categories, foods: result.0))
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            matches = []
            notice = "Ingredients could not load. Check your connection and try another search."
        }
    }

}
