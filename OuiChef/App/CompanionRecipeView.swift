import SwiftUI

struct CompanionRecipeView: View {
    @Bindable var store: CompanionStore
    @State var recipe: CompanionRecipe
    @State private var tab = "Ingredients"
    @State private var adjustments = false
    @State private var rename = false
    @State private var titleDraft = ""
    @State private var confirmDelete = false
    @State private var sharing = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var prepared = false
    @Environment(\.dismiss) private var dismiss
    private var existing: CookAttempt? { store.inProgress.first { $0.recipe.id == recipe.id && $0.recipe.version == recipe.version } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RecipePhoto(recipe: recipe).frame(height: 285)
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(recipe.title).font(Theme.serif(35)).foregroundStyle(Theme.plum).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                            if !recipe.summary.isEmpty { Text(recipe.summary).font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(3) }
                            HStack(spacing: 18) { Label(recipe.timeLabel, systemImage: "clock"); Label(recipe.servings.map { "\($0) servings" } ?? "Yield not specified", systemImage: "person") }.font(.caption).foregroundStyle(Theme.muted)
                            if let source = sourceURL { Link(destination: source) { Label("From \(recipe.creator ?? recipe.sourceName) ↗", systemImage: "link") }.font(.caption).foregroundStyle(Theme.plum) }
                            else { Text(recipe.sourceName).font(.caption).foregroundStyle(Theme.muted) }
                        }
                        Button { adjustments = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(Theme.berry).frame(width: 40, height: 40).background(Theme.blush.opacity(0.6), in: Circle())
                                VStack(alignment: .leading, spacing: 5) { Text("Your adjustments").font(.subheadline.weight(.medium)); Text(recipe.adjustmentSummary.isEmpty ? "Make it work for your kitchen" : recipe.adjustmentSummary).font(.caption).foregroundStyle(Theme.muted).lineLimit(2) }
                                Spacer(); Image(systemName: "chevron.right").font(.caption)
                            }.padding(12).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).accessibilityIdentifier("recipe-adjustments")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 28) { ForEach(["Ingredients", "Steps", "Notes", "Source"], id: \.self) { name in
                                Button { tab = name } label: { Text(name).font(.subheadline.weight(tab == name ? .semibold : .regular)).foregroundStyle(tab == name ? Theme.plum : Theme.muted).padding(.vertical, 12).overlay(alignment: .bottom) { if tab == name { Theme.plum.frame(height: 2) } } }.accessibilityAddTraits(tab == name ? .isSelected : [])
                            } }
                        }.overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                        if tab == "Ingredients" { ingredients }
                        else if tab == "Steps" { steps }
                        else if tab == "Notes" { notes }
                        else { source }
                        if !recipe.reviewNotes.isEmpty { RecipeReviewNotes(notes: recipe.reviewNotes) }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Theme.cream, in: UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25)).padding(.top, -24)
                }
            }.background(Theme.cream).foregroundStyle(Theme.ink).ignoresSafeArea(edges: .top)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 7) {
                        Button { if let existing { store.resume(existing.id); store.selectedRecipe = nil } else { store.start(recipe) } } label: {
                            HStack { Text(existing == nil ? "Start cooking" : existing!.isPreparing ? "Continue preparation" : "Resume cooking"); Image(systemName: "arrow.right") }
                        }.buttonStyle(FilledButton()).accessibilityIdentifier("start-recipe")
                        if existing != nil { Button("Start a new cook") { store.start(recipe, newAttempt: true) }.font(.caption).frame(minHeight: 32) }
                    }.padding(.horizontal, 24).padding(.vertical, 12).background(Theme.cream)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "arrow.left").frame(width: 36, height: 36) }.accessibilityLabel("Back") }
                    ToolbarItem(placement: .topBarTrailing) { Button { recipe.favorite.toggle(); editSaved { $0.favorite = recipe.favorite } } label: { Image(systemName: recipe.favorite ? "heart.fill" : "heart").frame(width: 36, height: 36) }.accessibilityLabel("Favorite recipe") }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Rename", systemImage: "pencil") { titleDraft = recipe.title; rename = true }
                            Button(recipe.archived == true ? "Restore to cookbook" : "Archive recipe", systemImage: "archivebox") { recipe.archived = recipe.archived != true; editSaved { $0.archived = recipe.archived }; dismiss() }
                            Button("Share recipe", systemImage: "square.and.arrow.up") { sharing = true; Task { shareURL = await store.shareRecipe(recipe); sharing = false; showShare = shareURL != nil } }.disabled(sharing).accessibilityIdentifier("share-recipe")
                            Button("Delete recipe", systemImage: "trash", role: .destructive) { confirmDelete = true }.accessibilityIdentifier("delete-recipe")
                        } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36) }.accessibilityLabel("Recipe options")
                    }
                }.toolbarBackground(.hidden, for: .navigationBar)
                .disabled(store.deletingRecipeIDs.contains(recipe.id))
                .alert("Delete \(recipe.title)?", isPresented: $confirmDelete) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete recipe", role: .destructive) { Task { await store.deleteRecipe(recipe.id) } }
                } message: { Text("This removes the recipe from your cookbook. Your cooking history and photos are kept.") }
        }
        .presentationBackground(Theme.cream)
        .onAppear { guard !prepared else { return }; prepared = true; do { recipe = try recipe.prepared(for: store.profile) } catch { store.error = error.localizedDescription } }
        .sheet(isPresented: $adjustments) { RecipeAdjustmentsView(store: store, recipe: $recipe) }
        .sheet(isPresented: $rename) { CookingTextEntry(title: "Rename recipe", hint: "Recipe name", message: "Give this recipe a name that feels like yours.", actionTitle: "Save name", text: $titleDraft) {
            let name = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 200 else { return "Use a name between 1 and 200 characters." }
            recipe.title = name; editSaved { $0.title = name }; return nil
        } }
        .sheet(isPresented: $showShare) { if let shareURL { RecipeShareSheet(url: shareURL, title: recipe.title).presentationDetents([.medium, .large]) } }
    }
    private var sourceURL: URL? { guard let url = URL(string: recipe.sourceURL), ["https", "http"].contains(url.scheme ?? "") else { return nil }; return url }
    private func editSaved(_ edit: (inout CompanionRecipe) -> Void) { var saved = store.recipes.first { $0.id == recipe.id } ?? recipe; edit(&saved); store.saveRecipe(saved) }
    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 22) {
            IngredientRows(recipe: recipe, ingredients: recipe.ingredients.filter { !$0.pantry })
            if recipe.ingredients.contains(where: \.pantry) { DisclosureGroup("Pantry basics") { IngredientRows(recipe: recipe, ingredients: recipe.ingredients.filter(\.pantry)).padding(.top, 14) }.font(.subheadline) }
            if !recipe.equipment.isEmpty { VStack(alignment: .leading, spacing: 10) { SectionEyebrow(title: "What you’ll need"); Text(recipe.equipment.joined(separator: " · ")).font(.subheadline) } }
            if !recipe.preparation.isEmpty { VStack(alignment: .leading, spacing: 10) { Text("Before you begin").font(Theme.serif(24)).foregroundStyle(Theme.plum); ForEach(recipe.preparation, id: \.self) { Text($0).font(.subheadline).lineSpacing(3) } } }
        }
    }
    private var steps: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                VStack(alignment: .leading, spacing: 9) {
                    SectionEyebrow(title: "\(index + 1) · \(step.stage)")
                    Text(step.title).font(Theme.serif(25)).foregroundStyle(Theme.plum)
                    Text(step.instruction).font(.body).lineSpacing(4)
                    if let cue = step.visualCue { Label(cue, systemImage: "eye").font(.subheadline).foregroundStyle(Theme.muted) }
                }
            }
        }
    }
    private var notes: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(recipe.adaptations, id: \.self) { Text($0).font(.subheadline) }
            ForEach(recipe.notes, id: \.self) { Text($0).font(.subheadline) }
            ForEach(recipe.ingredients.filter { $0.substitution != nil }) { ingredient in VStack(alignment: .leading, spacing: 6) { Text("Instead of \(ingredient.name)").font(.subheadline.weight(.semibold)); Text(ingredient.substitution ?? "").font(.subheadline).foregroundStyle(Theme.muted) } }
            if recipe.notes.isEmpty && recipe.adaptations.isEmpty { Text("A fresh page for your kitchen. Personal notes are saved with each cook.").font(.subheadline).foregroundStyle(Theme.muted) }
            ForEach(store.history.filter { $0.recipe.id == recipe.id }.prefix(3)) { attempt in VStack(alignment: .leading, spacing: 5) { Text(Date(timeIntervalSince1970: (attempt.finishedAt ?? 0) / 1000), style: .date).font(.caption).foregroundStyle(Theme.muted); Text(attempt.notes.isEmpty ? "Made by you" : attempt.notes).font(.subheadline) } }
        }
    }
    private var source: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(recipe.creator ?? recipe.sourceName).font(Theme.serif(25)).foregroundStyle(Theme.plum)
            if let sourceURL { Link("View the original recipe ↗", destination: sourceURL).font(.subheadline) }
            if let original = recipe.originalSource {
                Text("Original ingredients").font(.headline)
                ForEach(original.ingredients, id: \.id) { item in HStack(alignment: .top) { Text(item.name); Spacer(); Text(item.quantity).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing) }.font(.subheadline) }
                DisclosureGroup("Original instructions") { ForEach(original.actions, id: \.id) { Text($0.instruction).font(.subheadline).padding(.vertical, 8) } }
            }
            ForEach(Array(recipe.evidence.enumerated()), id: \.offset) { _, item in VStack(alignment: .leading, spacing: 5) { Text(item.origin == "source" ? "From the creator" : item.origin == "inferred" ? "Estimated" : "Supporting source").font(.caption.weight(.semibold)).foregroundStyle(Theme.berry); Text(item.detail).font(.subheadline) } }
        }
    }
}

struct IngredientRows: View {
    let recipe: CompanionRecipe
    let ingredients: [RecipeIngredient]
    var checked: Set<String>? = nil
    var toggle: ((String) -> Void)? = nil
    var body: some View {
        VStack(spacing: 0) { ForEach(ingredients) { item in
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: ingredientSymbol(item.name)).font(.system(size: 22, weight: .light)).foregroundStyle(Theme.plum).frame(width: 34).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) { Text(item.name).font(.body); if item.optional { Text("Optional").font(.caption).foregroundStyle(Theme.muted) }; if item.origin == "inferred" { Text("Estimated · review").font(.caption).foregroundStyle(Theme.warning) } }
                Spacer(minLength: 8)
                Text(item.quantity).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                if let checked, let toggle { Button { toggle(item.id) } label: { Image(systemName: checked.contains(item.id) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(checked.contains(item.id) ? Theme.plum : Theme.muted.opacity(0.5)).frame(width: 44, height: 44) }.accessibilityLabel("\(checked.contains(item.id) ? "Uncheck" : "Check") \(item.name)").accessibilityValue(checked.contains(item.id) ? "Selected" : "Not selected").accessibilityIdentifier("ingredient-check-\(item.id)") }
            }.padding(.vertical, 13)
            if item.id != ingredients.last?.id { Theme.line.frame(height: 1) }
        } }
    }
}

struct RecipeReviewNotes: View {
    let notes: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { Label("Before you cook", systemImage: "exclamationmark.circle").font(.subheadline.weight(.semibold)); ForEach(notes, id: \.self) { Text($0).font(.subheadline).lineSpacing(3) } }.foregroundStyle(Theme.warning).padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Theme.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct RecipeAdjustmentsView: View {
    let store: CompanionStore
    @Binding private var output: CompanionRecipe
    @State private var recipe: CompanionRecipe
    @State private var saveDefault = false
    @State private var error: String?
    @State private var beforeRestore: CompanionRecipe?
    @Environment(\.dismiss) private var dismiss
    init(store: CompanionStore, recipe: Binding<CompanionRecipe>) { self.store = store; _output = recipe; _recipe = State(initialValue: recipe.wrappedValue) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Make it yours.").font(Theme.serif(34)).foregroundStyle(Theme.plum)
                    Text("Adjust this preparation. Earlier cooking memories stay exactly as you made them.").font(.subheadline).foregroundStyle(Theme.muted)
                    if let servings = recipe.servings {
                        Stepper("\(servings) servings", onIncrement: { scale(servings + 1) }, onDecrement: { scale(servings - 1) }).font(.headline)
                        if let base = recipe.portionBaseline { Button("Reset to \(base.servings) servings") { scale(base.servings) }.font(.subheadline) }
                    } else { Text("The source didn’t specify a yield. Review the original recipe before changing portions.").font(.subheadline) }
                    if !recipe.adaptations.isEmpty { VStack(alignment: .leading, spacing: 12) { SectionEyebrow(title: "Already adjusted for you"); ForEach(recipe.adaptations, id: \.self) { Label($0, systemImage: "checkmark").font(.subheadline) } } }
                    if let original = recipe.originalSource {
                        DisclosureGroup("Compare with the original") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(original.ingredients, id: \.id) { source in
                                    if let adjusted = recipe.ingredients.first(where: { $0.id == source.id }), source.quantity != adjusted.quantity || source.name != adjusted.name {
                                        VStack(alignment: .leading, spacing: 5) { Text(source.name).font(.subheadline.weight(.medium)); Text("Original: \(source.quantity) \(source.name)\nThis cook: \(adjusted.quantity) \(adjusted.name)").font(.subheadline).foregroundStyle(Theme.muted) }
                                    }
                                }
                                Text("Restoring the source uses its original ingredients and instructions. Allergy and review notes remain visible.").font(.caption).foregroundStyle(Theme.muted)
                                if let beforeRestore { Button("Use imported adjustments") { recipe = beforeRestore; self.beforeRestore = nil } }
                                else { Button("Use the original recipe") { do { let restored = try recipe.restoringSource(); beforeRestore = recipe; recipe = restored } catch { self.error = error.localizedDescription } } }
                            }.padding(.top, 14)
                        }.font(.subheadline)
                    } else if !recipe.adaptations.isEmpty {
                        Text("This earlier import did not save an original version. Check the Source tab before overriding its adjustments.").font(.caption).foregroundStyle(Theme.muted)
                    }
                    if let baseline = recipe.portionBaseline {
                        VStack(alignment: .leading, spacing: 12) { SectionEyebrow(title: "Imported → This cook"); ForEach(recipe.ingredients) { ingredient in if let old = baseline.ingredients.first(where: { $0.id == ingredient.id }), old.quantity != ingredient.quantity { HStack { Text(ingredient.name); Spacer(); Text("\(old.quantity) → \(ingredient.quantity)").foregroundStyle(Theme.muted) }.font(.subheadline) } } }
                    }
                    if !recipe.reviewNotes.isEmpty { RecipeReviewNotes(notes: recipe.reviewNotes) }
                    Toggle("Use these portions next time", isOn: $saveDefault).font(.subheadline)
                    if let error { Text(error).font(.caption).foregroundStyle(Theme.warning) }
                    Button("Use these adjustments") { if saveDefault && !store.saveRecipe(recipe) { return }; output = recipe; dismiss() }.buttonStyle(FilledButton())
                }.padding(24)
            }.background(Theme.cream).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.presentationDetents([.large])
    }
    private func scale(_ servings: Int) { do { recipe = try recipe.scaled(to: servings); error = nil } catch { self.error = error.localizedDescription } }
}

struct RecipeShareSheet: UIViewControllerRepresentable {
    let url: URL
    let title: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: ["Cook \(title) with me in Oui Chef", url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
