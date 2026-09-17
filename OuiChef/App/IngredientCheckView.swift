import SwiftUI

struct IngredientCheckView: View {
    @Bindable var store: ChefStore
    let onEnd: () -> Void
    @State private var page = 0
    @State private var showPreferences = false
    @State private var expanded = Set<String>()

    var body: some View {
        if let session = store.session {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        if page > 0 {
                            Button { page -= 1 } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }
                                .accessibilityLabel("Back to previous check")
                        }
                        Text(["01 · PREFERENCES", "02 · INGREDIENTS", "03 · AMOUNTS", "04 · READY"][page])
                            .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.green)
                        Spacer()
                        Button(action: onEnd) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("End cooking session")
                    }
                    Text(["Your preferences", "Ingredient overview", session.recipe.style == .bread ? "Baking check" : "Adjust amounts", "Ready to cook"][page])
                        .font(Theme.serif(32)).accessibilityAddTraits(.isHeader)
                    Text(session.recipe.title).font(.subheadline).foregroundStyle(.secondary)
                    switch page {
                    case 0: preferences(session)
                    case 1: checklist(session)
                    case 2: amounts(session)
                    default: summary(session)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            .id(page).scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if page == 0 {
                        Button("Review ingredients") { page = 1 }.buttonStyle(FilledButton())
                    } else if page == 1 {
                        Text("\(session.confirmedIngredients.count) of \(session.recipe.ingredients.count) ingredients selected")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Continue") { page = 2 }.buttonStyle(FilledButton())
                            .disabled(!session.checksComplete || store.restriction(for: session.recipe) != nil)
                            .accessibilityIdentifier("check-continue")
                    } else if page == 2 {
                        Button("Confirm amounts & continue") {
                            if store.updateSession({ $0.confirmAllIngredients(true, at: Date()) }) { page = 3 }
                        }.buttonStyle(FilledButton()).accessibilityIdentifier("amounts-continue")
                        Text("Confirm you have the quantities shown above.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Cook with Oui Chef") { start(voice: true) }.buttonStyle(FilledButton())
                        Button("Cook without voice") { start(voice: false) }.font(.subheadline).frame(minHeight: 44)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 14).background(Theme.cream)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("preparation-footer")
            }
            .sheet(isPresented: $showPreferences) { OnboardingView(store: store, editing: true) }
        }
    }

    private func preferences(_ session: CookingSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your choices are checked against each ingredient, including ingredients inside sauces and mixes.")
                .font(.subheadline).foregroundStyle(.secondary)
            preferenceCard("Allergies", detail: store.preferences.allergies.isEmpty ? store.preferences.allergyAnswer : store.preferences.allergies.sorted().joined(separator: ", "), symbol: "heart")
            preferenceCard("Dislikes", detail: (store.preferences.dislikedFoodIDs ?? []).compactMap { store.catalog?.food($0)?.name }.sorted().joined(separator: ", "), symbol: "leaf")
            preferenceCard("Dietary style", detail: (store.preferences.dietary.sorted() + (store.preferences.avoidAlcohol ? ["Avoid alcohol"] : [])).joined(separator: ", "), symbol: "fork.knife")
            if let restriction = store.restriction(for: session.recipe) {
                Label(restriction, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Theme.orange).kitchenCard()
            } else {
                Label("No dietary or allergy conflicts found. Review taste notes and product labels with your ingredients.", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(Theme.green).kitchenCard()
            }
            Text("Supported swaps appear beside the ingredient. Taste adjustments are shown before you apply them.").font(.caption).foregroundStyle(.secondary)
            Button("Edit preferences") { showPreferences = true }.frame(minHeight: 44)
        }
    }

    private func preferenceCard(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            IngredientArtwork(food: nil, symbol: symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.serif(23))
                Text(detail.isEmpty ? "None selected" : detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.kitchenCard()
    }

    private func checklist(_ session: CookingSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("See what you'll need at a glance. Open a group for amounts and ingredient options.").font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: Double(session.confirmedIngredients.count), total: Double(session.recipe.ingredients.count)).tint(Theme.green)
            HStack {
                Button { _ = store.updateSession { $0.confirmAllIngredients(true, at: Date()) } } label: {
                    Label("I have the basics", systemImage: "checkmark")
                }.buttonStyle(.bordered).tint(Theme.green).controlSize(.large)
                Spacer()
                Button("Clear") { _ = store.updateSession { $0.confirmAllIngredients(false, at: Date()) } }.frame(minWidth: 44, minHeight: 44)
            }
            ForEach(store.catalog?.groups(for: session.recipe) ?? []) { group in
                DisclosureGroup(isExpanded: Binding(get: { expanded.contains(group.id) }, set: { value in
                    if value { expanded.insert(group.id) } else { expanded.remove(group.id) }
                })) {
                    VStack(spacing: 14) {
                        ForEach(group.ingredients) { ingredient in ingredientRow(ingredient, session: session) }
                    }.padding(.top, 16)
                } label: {
                    HStack(spacing: 14) {
                        IngredientArtwork(food: group.ingredients.first.flatMap { store.catalog?.food($0.foodID) }, symbol: group.symbol)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.name).font(Theme.serif(23))
                            Text(group.ingredients.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            let count = group.ingredients.filter { session.confirmedIngredients.contains($0.id) }.count
                            Text("\(count) / \(group.ingredients.count) confirmed").font(.caption).foregroundStyle(Theme.green)
                            let notes = group.ingredients.filter {
                                let review = store.catalog?.review(foodID: $0.foodID, preferences: store.preferences)
                                return !(review?.blocking.isEmpty ?? true) || !(review?.notes.isEmpty ?? true)
                            }.count
                            if notes > 0 { Text("\(notes) ingredient\(notes == 1 ? "" : "s") to review").font(.caption).foregroundStyle(Theme.orange) }
                        }
                    }
                }.kitchenCard().accessibilityIdentifier("ingredient-group-\(group.id)")
            }
            Button("Review details") { expanded = Set(store.catalog?.groups(for: session.recipe).map(\.id) ?? []) }.frame(minHeight: 44)
            checkRow("I've checked product labels", detail: "These ingredients suit my dietary needs, including packaging and cross-contact information.", checked: session.labelsChecked) {
                _ = store.updateSession { $0.labelsChecked.toggle(); $0.record("labels_checked", at: Date()) }
            }
            if let restriction = store.restriction(for: session.recipe) {
                Label(restriction, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Theme.orange)
            }
            Text("Missing something? Leave it unchecked until you have it. Kitchen items are recommendations and don't need confirmation.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func ingredientRow(_ ingredient: Ingredient, session: CookingSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            checkRow(ingredient.name, detail: ingredient.quantity, checked: session.confirmedIngredients.contains(ingredient.id)) {
                _ = store.updateSession { current in
                    if current.confirmedIngredients.contains(ingredient.id) {
                        current.confirmedIngredients.remove(ingredient.id)
                        current.record("ingredient_unchecked", at: Date())
                    } else { try current.confirmIngredient(ingredient.id, at: Date()) }
                }
            }
            let review = store.catalog?.review(foodID: ingredient.foodID, preferences: store.preferences) ?? IngredientReview()
            ForEach(review.blocking + review.notes, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.orange)
            }
            ForEach(ingredient.alternatives ?? []) { alternative in
                if alternative.foodID != ingredient.foodID {
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Use \(alternative.name)") {
                            _ = store.updateSession { try $0.selectAlternative(alternative.foodID, for: ingredient.id, at: Date()) }
                        }.frame(minHeight: 44)
                            .disabled(store.catalog?.review(foodID: alternative.foodID, preferences: store.preferences).blocking.isEmpty != true)
                        Text(alternative.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func checkRow(_ title: String, detail: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: checked ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(Theme.green)
            }.padding(12).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(checked ? Theme.sage.opacity(0.35) : Theme.cream, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(checked ? "Checked" : "Not checked")
    }
    private func amounts(_ session: CookingSession) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(session.recipe.style == .bread ? "Precision matters" : "Flexible recipe", systemImage: session.recipe.style == .bread ? "oven" : "fork.knife")
                .font(.subheadline.weight(.medium)).foregroundStyle(session.recipe.style == .bread ? Theme.orange : Theme.green)
                .padding(.horizontal, 14).padding(.vertical, 10).background(session.recipe.style == .bread ? Theme.orange.opacity(0.1) : Theme.sage.opacity(0.65), in: Capsule())
            Text(session.recipe.style == .bread ? "Keep close to the measured amounts. Water changes affect how the dough feels; flour and yeast stay fixed." : "Change servings or adjust the balance to your taste.")
                .font(.subheadline).foregroundStyle(.secondary)
            if session.started.isEmpty && session.recipe.maximumServings > 1 {
                Stepper("\(session.recipe.yieldLabel.capitalized): \(session.servings)", value: Binding(get: { session.servings }, set: { value in
                    _ = store.updateSession { try $0.setServings(value, at: Date()) }
                }), in: 1...session.recipe.maximumServings)
                .accessibilityIdentifier("prep-servings").padding(.vertical, 8)
            }
            ForEach(session.recipe.ratios) { option in
                if let original = store.recipes.first(where: { $0.id == session.recipe.id }),
                   let ingredient = original.ingredients.first(where: { $0.id == option.ingredientID }),
                   let base = original.ingredients.first(where: { $0.id == option.baseIngredientID }),
                   let ratio = option.preferredValue(store.preferences, defaultValue: ingredient.amount / base.amount),
                   let proposal = try? session.proposeRatio(option.id, value: ratio), abs(proposal.oldAmount - proposal.newAmount) > 0.001 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For your taste").font(Theme.serif(23))
                        Text("\(ingredient.name): \(proposal.oldAmount.formatted()) → \(proposal.newAmount.formatted()) \(ingredient.unit)").font(.subheadline)
                        Text(option.explanation).font(.caption).foregroundStyle(.secondary)
                        Button("Apply preference") { _ = store.updateSession { try $0.apply(proposal, at: Date()) } }.frame(minHeight: 44)
                    }.kitchenCard()
                }
            }
            ForEach(session.recipe.ingredients) { ingredient in
                VStack(alignment: .leading, spacing: 10) {
                    Text(ingredient.name).font(.subheadline.weight(.medium))
                    HStack(spacing: 12) {
                        Text(ingredient.quantity).font(.body.monospacedDigit()).foregroundStyle(Theme.green)
                        Spacer()
                        if let option = session.recipe.ratios.first(where: { $0.ingredientID == ingredient.id }),
                           let base = session.recipe.ingredients.first(where: { $0.id == option.baseIngredientID }),
                           let _ = try? session.proposeRatio(option.id, value: ingredient.amount / base.amount) {
                            let ratio = ingredient.amount / base.amount
                            amountButton("Decrease", symbol: "minus", ingredient: ingredient, option: option, ratio: max(option.minimum, ratio - option.step))
                                .disabled(ratio <= option.minimum + 0.00001)
                            amountButton("Increase", symbol: "plus", ingredient: ingredient, option: option, ratio: min(option.maximum, ratio + option.step))
                                .disabled(ratio >= option.maximum - 0.00001)
                        }
                    }
                    if let option = session.recipe.ratios.first(where: { $0.ingredientID == ingredient.id }) {
                        Text(option.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }.kitchenCard()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Kitchen items").font(Theme.serif(25))
                Text("Recommended for this recipe — no check needed.").font(.caption).foregroundStyle(.secondary)
                ForEach(session.recipe.tools, id: \.self) { tool in
                    Label(tool, systemImage: "fork.knife").font(.subheadline)
                }
            }.kitchenCard()
            Label(session.recipe.style == .bread ? "Baking is less flexible. Use the dough’s texture and rise to guide you." : "Amounts update together when you change servings. Cooking times still follow the recipe’s readiness checks.", systemImage: "lightbulb")
                .font(.subheadline).foregroundStyle(Theme.green).kitchenCard()
        }
    }

    private func amountButton(_ label: String, symbol: String, ingredient: Ingredient, option: RatioOption, ratio: Double) -> some View {
        Button {
            _ = store.updateSession { current in
                let proposal = try current.proposeRatio(option.id, value: ratio)
                try current.apply(proposal, at: Date())
            }
        } label: {
            Image(systemName: symbol).frame(width: 44, height: 44)
                .background(Theme.cream, in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityLabel("\(label) \(ingredient.name)")
    }

    private func summary(_ session: CookingSession) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Everything in place. Let's make something delicious.").font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                Label("Ingredient preferences reviewed", systemImage: "checkmark.circle")
                Label("\(session.recipe.ingredients.count) ingredients confirmed", systemImage: "checkmark.circle")
                Label("Product labels checked", systemImage: "checkmark.circle")
            }.font(.subheadline).foregroundStyle(Theme.green).kitchenCard()
            HStack {
                Text("Your confirmed amounts").font(Theme.serif(23))
                Spacer()
                Button("Edit") { page = 2 }.frame(minWidth: 44, minHeight: 44)
            }
            ForEach(session.recipe.ingredients) { ingredient in
                HStack {
                    Text(ingredient.name)
                    Spacer()
                    Text(ingredient.quantity).foregroundStyle(Theme.green)
                }.font(.subheadline)
            }
            Text("\(session.servings) \(session.recipe.yieldLabel) · Guided step by step").font(.caption).foregroundStyle(.secondary)
            VoiceOrb(size: 140).frame(maxWidth: .infinity)
            Text("Tell your chef when a step is done, or wait for a check-in.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func start(voice: Bool) {
        guard let session = store.session else { return }
        if let restriction = store.restriction(for: session.recipe) { store.error = restriction; return }
        if store.updateSession({ try $0.completePreparation(at: Date()) }), voice { store.openVoice() }
    }
}
