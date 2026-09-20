import SwiftUI

struct IngredientCheckView: View {
    let store: ChefStore
    let session: CookingSession
    let update: ((inout CookingSession) throws -> Void) -> Bool
    let onStart: (Bool) -> Void
    let onClose: () -> Void
    var closeLabel = "Back to recipes"
    @State private var pantryExpanded = false
    @State private var showPreferences = false

    private var pantry: [Ingredient] {
        session.recipe.ingredients.filter { store.catalog?.isPantryBasic($0, preferences: store.preferences) == true }
    }
    private var featured: [Ingredient] { session.recipe.ingredients.filter { ingredient in !pantry.contains { $0.id == ingredient.id } } }
    private var restriction: String? { store.restriction(for: session.recipe) }
    private var allConfirmed: Bool { Set(session.recipe.ingredients.map(\.id)).isSubset(of: session.confirmedIngredients) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack {
                    Text("For this recipe").font(Theme.serif(26)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button("I have everything") { _ = update { $0.confirmAllIngredients(true, at: Date()) } }
                        .font(.caption.weight(.medium)).frame(minHeight: 44)
                        .accessibilityIdentifier("confirm-all-ingredients")
                }
                VStack(spacing: 10) {
                    ForEach(featured) { ingredient in ingredientRow(ingredient) }
                }
                if !pantry.isEmpty { pantrySection }
                if let restriction {
                    Label(restriction, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Theme.orange)
                    Button("Edit preferences") { showPreferences = true }.frame(minHeight: 44)
                }
                DisclosureGroup("Adjust servings & balance") { amounts.padding(.top, 14) }
                    .font(.subheadline).tint(Theme.green).accessibilityIdentifier("adjust-amounts")
                let tools = store.preferences.toolsToMention(for: session.recipe)
                if !tools.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Have handy", systemImage: "fork.knife").font(.subheadline.weight(.medium))
                        Text(tools.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.sage.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                }
                DisclosureGroup("Recipe notes") { Text(session.recipe.source).font(.caption).padding(.top, 8) }
                    .font(.caption).tint(Theme.green)
            }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel(closeLabel)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleSaved(session.recipe.id) } label: {
                    Image(systemName: store.archive.savedRecipes.contains(session.recipe.id) ? "bookmark.fill" : "bookmark")
                        .frame(width: 44, height: 44)
                }.accessibilityLabel(store.archive.savedRecipes.contains(session.recipe.id) ? "Unsave recipe" : "Save recipe")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Text("Start confirms pantry basics and product labels checked for your dietary needs.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { onStart(true) } label: { HStack { Text("Start Chef AI"); Image(systemName: "arrow.right") } }
                    .buttonStyle(FilledButton()).disabled(!allConfirmed || restriction != nil)
                    .accessibilityIdentifier("start-chef")
                Button("Cook without voice") { onStart(false) }.font(.caption).frame(minHeight: 44)
                    .disabled(!allConfirmed || restriction != nil)
            }.padding(.horizontal, 22).padding(.top, 12).background(Theme.cream)
                .accessibilityElement(children: .contain).accessibilityIdentifier("preparation-footer")
        }
        .sheet(isPresented: $showPreferences) { OnboardingView(store: store, editing: true) }
        .onChange(of: session.revision) { _, _ in
            if pantry.contains(where: { !session.confirmedIngredients.contains($0.id) }) { pantryExpanded = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(restriction == nil ? "Preferences applied" : "Preferences need attention", systemImage: "leaf")
                .font(.caption.weight(.medium)).foregroundStyle(restriction == nil ? Theme.green : Theme.orange)
                .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.sage.opacity(0.7), in: Capsule())
            Text(session.recipe.title).font(.system(.title, design: .serif)).accessibilityAddTraits(.isHeader)
            Text("Confirm your ingredients, then let's cook.").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Text(session.recipe.chefName ?? "Chef Margarita")
                Spacer()
                Text("\(session.servings) \(session.recipe.yieldLabel) · \(session.recipe.timeLabel)")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pantrySection: some View {
        DisclosureGroup(isExpanded: $pantryExpanded) {
            VStack(spacing: 10) { ForEach(pantry) { ingredient in ingredientRow(ingredient) } }.padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pantry basics").font(.subheadline.weight(.medium))
                Text(pantry.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                Text(pantry.allSatisfy { session.confirmedIngredients.contains($0.id) } ? "Assumed on hand · tap to adjust" : "Check the amounts you have")
                    .font(.caption2).foregroundStyle(Theme.green)
            }
        }.padding(14).background(Theme.sage.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            .tint(Theme.green).accessibilityIdentifier("pantry-basics")
    }

    private func ingredientRow(_ ingredient: Ingredient) -> some View {
        let checked = session.confirmedIngredients.contains(ingredient.id)
        let food = store.catalog?.food(ingredient.foodID)
        let review = store.catalog?.review(foodID: ingredient.foodID, preferences: store.preferences) ?? IngredientReview()
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                _ = update { current in
                    if current.confirmedIngredients.contains(ingredient.id) {
                        current.confirmedIngredients.remove(ingredient.id)
                        current.record("ingredient_unchecked", at: Date())
                    } else { try current.confirmIngredient(ingredient.id, at: Date()) }
                }
            } label: {
                HStack(spacing: 12) {
                    IngredientArtwork(food: food, symbol: store.catalog?.categoryPath(food?.categoryID).last?.symbol ?? "leaf", size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ingredient.name).font(.system(.body, design: .serif)).foregroundStyle(Theme.ink)
                        Text(ingredient.quantity).font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 3) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle").font(.title2)
                        Text(checked ? "Have it" : "Confirm").font(.caption2)
                    }.foregroundStyle(Theme.green)
                }.frame(minHeight: 54).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(ingredient.name)
                .accessibilityValue("\(checked ? "Checked" : "Not checked"), \(ingredient.quantity)")
                .accessibilityIdentifier("ingredient-\(ingredient.id)")
            if let original = session.sourceRecipe?.ingredients.first(where: { $0.id == ingredient.id }) {
                if original.foodID != ingredient.foodID {
                    Label("Instead of \(original.name.lowercased())", systemImage: "arrow.left.arrow.right").font(.caption).foregroundStyle(Theme.green)
                } else if abs(original.amount * (original.scales ? Double(session.servings) / Double(session.recipe.baseServings) : 1) - ingredient.amount) > 0.001 {
                    Label("Adjusted amount", systemImage: "leaf").font(.caption).foregroundStyle(Theme.green)
                }
            }
            ForEach(review.blocking + review.notes, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.orange)
            }
            if !(ingredient.alternatives ?? []).isEmpty && session.started.isEmpty {
                DisclosureGroup("Substitutions") {
                    ForEach(ingredient.alternatives ?? []) { alternative in
                        if alternative.foodID != ingredient.foodID {
                            Button("Use \(alternative.name)") { _ = update { try $0.selectAlternative(alternative.foodID, for: ingredient.id, at: Date()) } }
                                .font(.subheadline).frame(minHeight: 44)
                                .disabled(store.catalog?.review(foodID: alternative.foodID, preferences: store.preferences).blocking.isEmpty != true)
                            Text(alternative.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.font(.caption).tint(Theme.green).accessibilityIdentifier("ingredient-options-\(ingredient.id)")
            }
        }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.green.opacity(0.1)))
    }

    private var amounts: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.started.isEmpty && session.recipe.maximumServings > 1 {
                Stepper("\(session.recipe.yieldLabel.capitalized): \(session.servings)", value: Binding(get: { session.servings }, set: { value in
                    _ = update { try $0.setServings(value, at: Date()) }
                }), in: 1...session.recipe.maximumServings).accessibilityIdentifier("prep-servings")
            }
            ForEach(session.recipe.ratios) { option in
                if let ingredient = session.recipe.ingredients.first(where: { $0.id == option.ingredientID }),
                   let base = session.recipe.ingredients.first(where: { $0.id == option.baseIngredientID }),
                   let _ = try? session.proposeRatio(option.id, value: ingredient.amount / base.amount) {
                    let ratio = ingredient.amount / base.amount
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { Text(ingredient.name); Text(ingredient.quantity).foregroundStyle(Theme.green) }
                            Spacer()
                            amountButton("Decrease", symbol: "minus", ingredient: ingredient, option: option, ratio: max(option.minimum, ratio - option.step))
                                .disabled(ratio <= option.minimum + 0.00001)
                            amountButton("Increase", symbol: "plus", ingredient: ingredient, option: option, ratio: min(option.maximum, ratio + option.step))
                                .disabled(ratio >= option.maximum - 0.00001)
                        }.font(.subheadline)
                        Text(option.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if session.recipe.style == .bread {
                Label("Baking needs precise amounts. Check the dough's texture and rise as you cook.", systemImage: "oven")
                    .font(.caption).foregroundStyle(Theme.orange)
            }
        }
    }

    private func amountButton(_ label: String, symbol: String, ingredient: Ingredient, option: RatioOption, ratio: Double) -> some View {
        Button {
            _ = update { current in try current.apply(current.proposeRatio(option.id, value: ratio), at: Date()) }
        } label: { Image(systemName: symbol).frame(width: 44, height: 44).background(.white, in: RoundedRectangle(cornerRadius: 10)) }
            .accessibilityLabel("\(label) \(ingredient.name)")
    }
}
