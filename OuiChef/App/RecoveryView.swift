import SwiftUI

struct RecoveryView: View {
    let store: ChefStore
    @State private var ingredientID = ""
    @State private var amount = ""
    @State private var recoveryAmount = ""
    @State private var proposed: RecoveryPlan?

    var body: some View {
        if let session = store.session {
            VStack(alignment: .leading, spacing: 16) {
                if let plan = session.pendingRecovery {
                    Text("Let's adjust this batch").font(Theme.serif(25))
                    Text(plan.instruction).font(.subheadline)
                    Text("Check the extra ingredients you have before adding them.").font(.caption)
                    ForEach(session.recipe.ingredients.filter { plan.additions[$0.id] != nil }) { ingredient in
                        let checked = session.recoveryIngredientsConfirmed?.contains(ingredient.id) == true
                        Button {
                            _ = store.updateSession { try $0.confirmRecoveryIngredient(ingredient.id, checked: !checked, at: Date()) }
                        } label: {
                            Label("\(plan.additions[ingredient.id]!.formatted()) \(ingredient.unit) extra \(ingredient.name)", systemImage: checked ? "checkmark.circle.fill" : "circle")
                                .frame(minHeight: 44)
                        }.accessibilityValue(checked ? "Checked" : "Not checked")
                    }
                    Button("I've added these ingredients") {
                        if let restriction = store.restriction(for: session.recipe) { store.error = restriction; return }
                        if store.updateSession({ try $0.completeRecovery(at: Date()) }) { store.say(plan.criterion) }
                    }.buttonStyle(FilledButton()).disabled(!Set(plan.additions.keys).isSubset(of: session.recoveryIngredientsConfirmed ?? []))
                    Button("Cancel — I haven't added anything") { _ = store.updateSession { $0.cancelRecovery(at: Date()) } }.frame(minHeight: 44)
                } else {
                    DisclosureGroup("Correct or adjust this recipe") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Record what you actually used. Then choose a supported correction, or ask your chef for help.").font(.caption)
                            Picker("Ingredient", selection: $ingredientID) {
                                Text("Choose ingredient").tag("")
                                ForEach(session.recipe.ingredients) { Text($0.name).tag($0.id) }
                            }
                            if let ingredient = session.recipe.ingredients.first(where: { $0.id == ingredientID }) {
                                HStack {
                                    TextField("Actual total", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("actual-ingredient-amount")
                                    Text(ingredient.unit)
                                }
                                Button("Record actual amount") {
                                    guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")) else { store.error = "Enter a valid amount."; return }
                                    _ = store.updateSession { try $0.reportAmount(ingredient.id, amount: value, unit: ingredient.unit, at: Date()) }
                                }.frame(minHeight: 44)
                            }
                            if session.correctionUndo?.revision == session.revision {
                                Button("Undo incorrect quantity report / edit") { _ = store.updateSession { try $0.undoCorrection(at: Date()) } }.frame(minHeight: 44)
                            }
                            ForEach(session.recipe.recoveryOptions ?? []) { option in
                                if let nodeID = option.nodeIDs.first(where: { session.started.contains($0) && !session.hasStartedDescendant(of: $0) }) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(option.title).font(.headline)
                                        if option.kind == .addition, let ingredient = session.recipe.ingredients.first(where: { $0.id == option.ingredientIDs.first }) {
                                            let scale = Double(session.servings) / Double(session.recipe.baseServings)
                                            Text("\((option.minimum * scale).formatted())–\((option.maximum * scale).formatted()) \(ingredient.unit) extra per adjustment").font(.caption)
                                            TextField("Extra amount", text: $recoveryAmount).keyboardType(.decimalPad)
                                        }
                                        Button("Preview \(option.title.lowercased())") {
                                            do {
                                                if let restriction = store.restriction(for: session.recipe) { throw CookingError.invalid(restriction) }
                                                proposed = try session.proposeRecovery(option.id, value: option.kind == .balance ? 1 : Double(recoveryAmount.replacingOccurrences(of: ",", with: ".")) ?? 0, nodeID: nodeID)
                                            } catch { store.error = error.localizedDescription }
                                        }.frame(minHeight: 44)
                                    }
                                }
                            }
                            if let proposed {
                                Text(proposed.instruction).font(.subheadline)
                                ForEach(session.recipe.ingredients.filter { proposed.additions[$0.id] != nil }) { ingredient in
                                    Text("Add \(proposed.additions[ingredient.id]!.formatted()) \(ingredient.unit) \(ingredient.name)").font(.subheadline)
                                }
                                Button("Use this recovery plan") {
                                    _ = store.updateSession { try $0.acceptRecovery(proposed, at: Date()) }
                                    self.proposed = nil
                                }.buttonStyle(FilledButton())
                            }
                        }.padding(.top, 12)
                    }
                }
            }.kitchenCard()
        }
    }
}
