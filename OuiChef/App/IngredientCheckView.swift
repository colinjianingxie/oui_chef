import SwiftUI

struct IngredientCheckView: View {
    @Bindable var store: ChefStore
    let onEnd: () -> Void
    @State private var page = 0

    var body: some View {
        if let session = store.session {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        if page > 0 {
                            Button { page -= 1 } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }
                                .accessibilityLabel("Back to previous check")
                        }
                        Text(["01 · CHECK", "02 · ADJUST", "03 · READY"][page])
                            .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.green)
                        Spacer()
                        Button(action: onEnd) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("End cooking session")
                    }
                    Text(["Check your ingredients", session.recipe.style == .bread ? "Baking check" : "Adjust amounts", "Ingredient check complete"][page])
                        .font(Theme.serif(32)).accessibilityAddTraits(.isHeader)
                    Text(session.recipe.title).font(.subheadline).foregroundStyle(.secondary)
                    if page == 0 { checklist(session) }
                    else if page == 1 { amounts(session) }
                    else { summary(session) }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            .id(page)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if page == 0 {
                        Text(session.confirmedIngredients.count == session.recipe.ingredients.count && !session.checksComplete
                             ? "Check equipment and labels below to continue"
                             : "\(session.confirmedIngredients.count) of \(session.recipe.ingredients.count) ingredients selected")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Continue") { page = 1 }.buttonStyle(FilledButton())
                            .disabled(!session.checksComplete).accessibilityIdentifier("check-continue")
                    } else if page == 1 {
                        Button("Confirm amounts & continue") {
                            if store.updateSession({ $0.confirmAllIngredients(true, at: Date()) }) { page = 2 }
                        }.buttonStyle(FilledButton()).accessibilityIdentifier("amounts-continue")
                        Text("Confirm you have the quantities shown above.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Cook with Oui Chef") { start(voice: true) }.buttonStyle(FilledButton())
                        Button("Cook without voice") { start(voice: false) }.font(.subheadline).frame(minHeight: 44)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 14).background(Theme.cream)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("preparation-footer")
            }
        }
    }

    private func checklist(_ session: CookingSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tap to confirm what you have at home.").font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: Double(session.confirmedIngredients.count), total: Double(session.recipe.ingredients.count)).tint(Theme.green)
            HStack {
                Button { _ = store.updateSession { $0.confirmAllIngredients(true, at: Date()) } } label: {
                    Label("Select all I have", systemImage: "checkmark")
                }.buttonStyle(.bordered).tint(Theme.green).controlSize(.large)
                Spacer()
                Button("Clear") { _ = store.updateSession { $0.confirmAllIngredients(false, at: Date()) } }
                    .frame(minWidth: 44, minHeight: 44)
            }
            VStack(spacing: 4) {
                ForEach(session.recipe.ingredients) { ingredient in
                    checkRow(ingredient.name, detail: ingredient.quantity, checked: session.confirmedIngredients.contains(ingredient.id)) {
                        _ = store.updateSession { current in
                            if current.confirmedIngredients.contains(ingredient.id) {
                                current.confirmedIngredients.remove(ingredient.id)
                                current.record("ingredient_unchecked", at: Date())
                            } else { try current.confirmIngredient(ingredient.id, at: Date()) }
                        }
                    }
                }
            }
            Text("Within reach").font(Theme.serif(25))
            checkRow("I have these tools", detail: session.recipe.tools.joined(separator: " · "), checked: Set(session.recipe.tools).isSubset(of: session.confirmedTools)) {
                _ = store.updateSession { current in
                    current.confirmedTools = Set(current.recipe.tools).isSubset(of: current.confirmedTools) ? [] : Set(current.recipe.tools)
                    current.record("tools_checked", at: Date())
                }
            }
            checkRow("I've checked product labels", detail: "These ingredients and tools suit my dietary needs, including cross-contact information.", checked: session.labelsChecked) {
                _ = store.updateSession { $0.labelsChecked.toggle(); $0.record("labels_checked", at: Date()) }
            }
            if let restriction = store.restriction(for: session.recipe) {
                Label(restriction, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Theme.orange)
            }
            Text("Missing something? Leave it unchecked until you have it. Cooking starts after your checks are complete.")
                .font(.caption).foregroundStyle(.secondary)
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
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(checked ? Theme.green : Theme.green.opacity(0.4))
            }.padding(14).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(checked ? Theme.sage.opacity(0.35) : .white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
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
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.green)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            Text("You're all set!").font(Theme.serif(26)).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 14) {
                Label("\(session.recipe.ingredients.count) ingredients confirmed", systemImage: "checkmark.circle.fill")
                Label("Equipment and labels checked", systemImage: "checkmark.circle.fill")
                Label("\(session.servings) \(session.recipe.yieldLabel)", systemImage: "person.2")
            }.font(.subheadline).foregroundStyle(Theme.green).kitchenCard()
            HStack {
                Text("Your confirmed amounts").font(Theme.serif(23))
                Spacer()
                Button("Edit") { page = 1 }.frame(minWidth: 44, minHeight: 44)
            }
            ForEach(session.recipe.ingredients) { ingredient in
                HStack {
                    Text(ingredient.name)
                    Spacer()
                    Text(ingredient.quantity).foregroundStyle(Theme.green)
                }.font(.subheadline)
            }
            Label("Oui Chef will guide you using these amounts. Tell your chef when a step is done, or wait for a check-in.", systemImage: "leaf")
                .font(.subheadline).foregroundStyle(Theme.green).kitchenCard()
            VoiceOrb(size: 140).frame(maxWidth: .infinity)
        }
    }

    private func start(voice: Bool) {
        guard let session = store.session else { return }
        if let restriction = store.restriction(for: session.recipe) { store.error = restriction; return }
        if store.updateSession({ try $0.completePreparation(at: Date()) }), voice { store.openVoice() }
    }
}
