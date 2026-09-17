import SwiftUI

struct KitchenView: View {
    @Bindable var store: ChefStore
    @State private var tab = "Home"
    @State private var query = ""
    @State private var filter = "All"
    @State private var showSettings = false
    @State private var voiceOrigin: CGPoint?
    @Namespace private var voiceTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filteredRecipes: [Recipe] {
        store.recipes.filter { recipe in
            (query.isEmpty || (recipe.title + " " + recipe.tags.joined(separator: " ") + " " + recipe.style.rawValue).localizedCaseInsensitiveContains(query))
            && (filter == "All" || filter == "Free" || recipe.tags.contains(filter))
            && (tab != "Saved" || store.archive.savedRecipes.contains(recipe.id))
        }
    }

    var body: some View {
        ZStack {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                if store.session != nil {
                    CookingView(store: store)
                } else if tab == "Profile" {
                    ProfileView(store: store)
                } else {
                    catalog
                }
            }
            .foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Oui Chef").font(Theme.serif(24)) }
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "leaf").foregroundStyle(Theme.green).accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Cooking preferences")
                }
            }
            .toolbarBackground(Theme.cream, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if store.session == nil { tabBar }
            }
        }
        .blur(radius: store.showingVoice && !reduceMotion ? 4 : 0)
        .allowsHitTesting(!store.showingVoice)
        .accessibilityHidden(store.showingVoice)

        GeometryReader { geometry in
            let frame = geometry.frame(in: .named("kitchen"))
            let origin = voiceOrigin ?? CGPoint(x: frame.midX, y: frame.maxY - geometry.safeAreaInsets.bottom - 33)
            Circle().fill(.white)
                .frame(width: 54, height: 54)
                .scaleEffect(store.showingVoice ? hypot(frame.width, frame.height) * 2 / 54 : 1)
                .position(x: origin.x - frame.minX, y: origin.y - frame.minY)
                .opacity(store.showingVoice ? 1 : 0)
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)

        if store.showingVoice {
            VoiceSessionView(store: store, transition: voiceTransition)
                .transition(.opacity).zIndex(1)
        }
        }
        .coordinateSpace(name: "kitchen")
        .onPreferenceChange(VoiceOriginKey.self) { if let origin = $0 { voiceOrigin = origin } }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: store.showingVoice)
        .sheet(isPresented: $showSettings) { OnboardingView(store: store, editing: true) }
        .sheet(item: Binding(get: { store.recipes.first { $0.id == store.selectedRecipeID } }, set: { store.selectedRecipeID = $0?.id })) { recipe in
            RecipeDetailView(store: store, recipe: recipe)
        }
    }

    private var catalog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tab == "Home" ? "YOUR KITCHEN, A LITTLE CALMER" : "A LITTLE INSPIRATION").font(.system(size: 10, weight: .semibold)).tracking(2.2).foregroundStyle(Theme.green)
                    Text(tab == "Home" ? "Good food\nstarts here." : tab == "Saved" ? "Your favorites." : "Something\ndelicious awaits.")
                        .font(Theme.serif(43)).lineSpacing(-1).accessibilityAddTraits(.isHeader)
                    Text("Cook, learn, and enjoy the little things.").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.green)
                    TextField("What would you like to cook?", text: $query).font(.subheadline).submitLabel(.search)
                    Button { store.openVoice() } label: { Image(systemName: "mic") }
                        .accessibilityLabel("Find a recipe by voice")
                }.padding(16).background(.white.opacity(0.75), in: Capsule())

                if tab == "Home" && query.isEmpty {
                    HStack(spacing: 12) {
                        Button { store.openVoice() } label: { VoiceOrb(size: 108) }
                            .accessibilityLabel("Start guided voice")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A sous chef\nthat listens.").font(Theme.serif(25))
                            Text(store.voice.enabled ? store.voice.status : "Try saying “pasta” or “margarita”.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 8).padding(.vertical, 8)
                    if store.voice.enabled { Text(store.chefMessage).font(.subheadline).kitchenCard() }
                }

                HStack {
                    Text(tab == "Saved" ? "Saved recipes" : "From our kitchen").font(Theme.serif(25))
                    Spacer()
                    Text("\(filteredRecipes.count) recipes").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["All", "Free", "Dinner", "Baking", "Drinks"], id: \.self) { item in
                            Button { filter = item } label: {
                                Text(item).font(.subheadline).padding(.horizontal, 18).padding(.vertical, 10)
                                    .background(filter == item ? Theme.green : .white.opacity(0.65), in: Capsule())
                                    .foregroundStyle(filter == item ? .white : Theme.ink)
                            }.accessibilityAddTraits(filter == item ? .isSelected : [])
                        }
                    }
                }
                if filteredRecipes.isEmpty {
                    ContentUnavailableView(tab == "Saved" ? "Your recipe box is waiting" : "No recipes found", systemImage: "leaf", description: Text(tab == "Saved" ? "Tap a bookmark to save something delicious." : "Try pasta, bread, or margarita."))
                }
                ForEach(filteredRecipes) { recipe in recipeCard(recipe) }
                Text("SIMPLE INGREDIENTS. EXTRAORDINARY MOMENTS.")
                    .font(.system(size: 9, weight: .medium)).tracking(1.7).foregroundStyle(Theme.green)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
            }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
        }
    }

    private func recipeCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { store.selectedRecipeID = recipe.id } label: {
                RecipeArtwork(style: recipe.style).frame(height: 185)
                    .overlay(alignment: .topLeading) {
                        Label(recipe.minutes, systemImage: "clock").font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.cream, in: Capsule()).padding(14)
                    }
            }.buttonStyle(.plain).accessibilityLabel("View \(recipe.title)")
            HStack(alignment: .top) {
                Button { store.selectedRecipeID = recipe.id } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(recipe.style.name.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.green)
                        Text(recipe.title).font(Theme.serif(27))
                        Text("Anonymous Chef · Free").font(.caption).foregroundStyle(Theme.green)
                        Text(recipe.subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                }.buttonStyle(.plain)
                Spacer(minLength: 4)
                Button { store.toggleSaved(recipe.id) } label: {
                    Image(systemName: store.archive.savedRecipes.contains(recipe.id) ? "bookmark.fill" : "bookmark").font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel(store.archive.savedRecipes.contains(recipe.id) ? "Unsave \(recipe.title)" : "Save \(recipe.title)")
            }.padding(20)
        }.background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 24)).clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var tabBar: some View {
        HStack {
            tabButton("Home", symbol: "house")
            tabButton("Recipes", symbol: "book.closed")
            Group {
                if store.showingVoice {
                    Color.clear.frame(width: 54, height: 54)
                } else {
                    Button { store.openVoice() } label: {
                        Image(systemName: "mic.fill").font(.title3).foregroundStyle(.white)
                            .frame(width: 54, height: 54).background(Theme.green, in: Circle())
                    }
                    .matchedGeometryEffect(id: "voice-control", in: voiceTransition)
                    .accessibilityLabel("Start voice commands")
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: VoiceOriginKey.self, value: CGPoint(x: geometry.frame(in: .named("kitchen")).midX, y: geometry.frame(in: .named("kitchen")).midY))
                }
            }
            tabButton("Saved", symbol: "bookmark")
            tabButton("Profile", symbol: "person")
        }.padding(.horizontal, 15).padding(.top, 12).padding(.bottom, 6)
            .background(Theme.cream, ignoresSafeAreaEdges: .bottom)
            .overlay(alignment: .top) { Theme.green.opacity(0.1).frame(height: 1) }
    }
    private func tabButton(_ title: String, symbol: String) -> some View {
        Button { tab = title; query = ""; filter = "All" } label: {
            VStack(spacing: 5) { Image(systemName: symbol + (tab == title ? ".fill" : "")).font(.system(size: 19)); Text(title).font(.system(size: 10)) }
                .foregroundStyle(tab == title ? Theme.green : .secondary).frame(maxWidth: .infinity).frame(minHeight: 48)
        }.accessibilityAddTraits(tab == title ? .isSelected : [])
    }
}

private struct VoiceOriginKey: PreferenceKey {
    static var defaultValue: CGPoint? { nil }
    static func reduce(value: inout CGPoint?, nextValue: () -> CGPoint?) { value = nextValue() ?? value }
}

struct RecipeDetailView: View {
    @Bindable var store: ChefStore
    let recipe: Recipe
    @State private var servings = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    RecipeArtwork(style: recipe.style).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 24))
                    Text(recipe.title).font(Theme.serif(36))
                    Text("Anonymous Chef · Free").font(.subheadline).foregroundStyle(Theme.green)
                    Text(recipe.subtitle).foregroundStyle(.secondary)
                    HStack(spacing: 20) { Label(recipe.minutes, systemImage: "clock"); Label(recipe.style.name, systemImage: "leaf") }.font(.caption)
                    Stepper("\(recipe.yieldLabel.capitalized): \(servings)", value: $servings, in: 1...recipe.maximumServings)
                    Text("Before we cook").font(Theme.serif(28))
                    Text("A quick check for a smoother cooking experience.").font(.subheadline).foregroundStyle(.secondary)
                    prepCard("Preferences", detail: "Applied to the ingredients you use", symbol: "heart")
                    prepCard("Ingredients", detail: "Grouped for an easy check", symbol: "carrot")
                    prepCard("Kitchen items", detail: "Helpful recommendations · no verification", symbol: "fork.knife")
                    DisclosureGroup("What you’ll need") {
                        ForEach(recipe.ingredients) { ingredient in
                            HStack {
                                Text(ingredient.name)
                                Spacer()
                                Text((ingredient.amount * (ingredient.scales ? Double(servings) / Double(recipe.baseServings) : 1)).formatted(.number.precision(.fractionLength(0...1))) + " " + ingredient.unit)
                                    .foregroundStyle(.secondary)
                            }.font(.subheadline).padding(.vertical, 5)
                        }
                    }.kitchenCard()
                    if let restriction = store.restriction(for: recipe) {
                        Label(restriction, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Theme.orange).kitchenCard()
                    }
                    DisclosureGroup("Recipe notes") { Text(recipe.source).font(.caption).textSelection(.enabled).padding(.top, 8) }
                }.padding(24)
            }
            .background(Theme.cream).foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    store.choose(recipe, servings: servings)
                    if store.session?.recipe.id == recipe.id { dismiss() }
                } label: { Label("Start prep flow", systemImage: "arrow.right") }
                    .buttonStyle(FilledButton())
                    .padding(20).background(Theme.cream)
            }
        }.onAppear { servings = recipe.baseServings }
    }

    private func prepCard(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 16) {
            IngredientArtwork(food: nil, symbol: symbol)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(Theme.serif(24))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }.kitchenCard()
    }
}
