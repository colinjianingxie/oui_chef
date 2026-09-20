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

    private var filteredRecipes: [RecipeSummary] {
        store.recipeCards.filter { tab != "Saved" || store.archive.savedRecipes.contains($0.id) }
    }
    private var catalogQuery: String { [query, filter, tab, store.selectedSetID ?? "", String(store.previewDrafts)].joined(separator: "|") }
    private var classification: String? { filter == "All" ? nil : filter }

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
                    if store.session == nil { Image(systemName: "leaf").foregroundStyle(Theme.green).accessibilityHidden(true) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
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
        .sheet(isPresented: Binding(get: { store.photoAttemptID != nil }, set: { if !$0 { store.photoAttemptID = nil } })) {
            if let id = store.photoAttemptID { DishPhotoView(store: store, attemptID: id, accountID: store.accountID) }
        }
        .sheet(isPresented: $showSettings) { OnboardingView(store: store, editing: true) }
        .sheet(isPresented: Binding(get: { store.selectedRecipeID != nil }, set: { if !$0 { store.selectedRecipeID = nil } })) {
            if let recipe = store.selectedRecipe { RecipeDetailView(store: store, recipe: recipe) }
            else {
                NavigationStack {
                    Group {
                        if store.detailLoading { ProgressView("Opening recipe…") }
                        else { ContentUnavailableView("Recipe unavailable", systemImage: "book.closed", description: Text(store.detailError ?? "Please try again.")) }
                    }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { store.selectedRecipeID = nil } } }
                }
            }
        }
        .task(id: catalogQuery) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await store.loadCards(search: query, classification: classification, saved: tab == "Saved")
        }
    }

    private var catalog: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 25) {
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

                if let notice = store.catalogNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                if store.catalogAdmin {
                    Toggle("Preview drafts", isOn: $store.previewDrafts).tint(Theme.green)
                        .onChange(of: store.previewDrafts) { _, _ in store.selectedSetID = nil; query = ""; filter = "All" }
                }
                if !store.previewDrafts && tab != "Saved" {
                    Text("Recipe sets").font(Theme.serif(25))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Button("All recipes") { store.selectedSetID = nil }.buttonStyle(.bordered)
                            ForEach(store.recipeSets) { set in
                                Button { store.selectedSetID = set.id } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(set.title).font(.headline)
                                        Text(set.chefName + " · " + set.accessLabel).font(.caption)
                                        Text(set.discoveryTags.compactMap { id in store.classifications.first { $0.id == id }?.name }.joined(separator: " · ")).font(.caption2)
                                    }.padding(14).background(store.selectedSetID == set.id ? Theme.sage : .white, in: RoundedRectangle(cornerRadius: 16))
                                }.buttonStyle(.plain)
                            }
                            if store.hasMoreSets { Button("More sets") { Task { await store.moreSets() } } }
                        }
                    }
                }
                HStack {
                    Text(tab == "Saved" ? "Saved recipes" : "From our kitchen").font(Theme.serif(25))
                    Spacer()
                    Text("\(filteredRecipes.count) recipes").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["All"] + store.classifications.map(\.id), id: \.self) { item in
                            Button { filter = item } label: {
                                Text(store.classifications.first { $0.id == item }?.name ?? item).font(.subheadline).padding(.horizontal, 18).padding(.vertical, 10)
                                    .background(filter == item ? Theme.green : .white.opacity(0.65), in: Capsule())
                                    .foregroundStyle(filter == item ? .white : Theme.ink)
                            }.accessibilityAddTraits(filter == item ? .isSelected : [])
                        }
                    }
                }
                if filteredRecipes.isEmpty && !store.catalogLoading {
                    ContentUnavailableView(store.previewDrafts ? "No drafts to review" : tab == "Saved" ? "Your recipe box is waiting" : "No recipes found", systemImage: "leaf", description: Text(store.previewDrafts ? "Imported drafts appear here before you publish them." : tab == "Saved" ? "Tap a bookmark to save something delicious." : "Try pasta, bread, or margarita."))
                }
                ForEach(filteredRecipes) { recipe in recipeCard(recipe) }
                if store.catalogLoading { ProgressView("Loading recipes…").frame(maxWidth: .infinity) }
                else if store.hasMoreRecipes {
                    Button("Load more recipes") { Task { await store.loadCards(search: query, classification: classification, more: true, saved: tab == "Saved") } }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
                Text("SIMPLE INGREDIENTS. EXTRAORDINARY MOMENTS.")
                    .font(.system(size: 9, weight: .medium)).tracking(1.7).foregroundStyle(Theme.green)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
            }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
        }.refreshable { await store.loadLibrary(); await store.loadCards(search: query, classification: classification, saved: tab == "Saved") }
    }

    private func recipeCard(_ recipe: RecipeSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { store.openRecipe(recipe.id) } label: {
                RecipeArtwork(style: recipe.style).frame(height: 185)
                    .overlay(alignment: .topLeading) {
                        Label(recipe.timeLabel, systemImage: "clock").font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.cream, in: Capsule()).padding(14)
                    }
            }.buttonStyle(.plain).accessibilityLabel("View \(recipe.title)")
            HStack(alignment: .top) {
                Button { store.openRecipe(recipe.id) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(recipe.style.name.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.green)
                        Text(recipe.title).font(Theme.serif(27))
                        Text(recipe.chefName + (store.previewDrafts ? " · Draft preview" : "")).font(.caption).foregroundStyle(Theme.green)
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
        Button { tab = title; query = ""; filter = "All"; store.selectedSetID = nil; if title == "Saved" { store.previewDrafts = false } } label: {
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
    let store: ChefStore
    let recipe: Recipe
    @State private var preparation: CookingSession?
    @State private var preparationError: String?
    @State private var confirmPublish = false
    @State private var publishing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let preparation {
                    IngredientCheckView(store: store, session: preparation, update: updatePreparation,
                                        onStart: { voice in
                        if store.startCooking(preparation, voice: voice) { dismiss() }
                    }, onClose: { dismiss() })
                } else {
                    ContentUnavailableView("Ingredients unavailable", systemImage: "basket", description: Text(preparationError ?? "Please reopen this recipe."))
                }
            }
            .background(Theme.cream).foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Oui Chef").font(Theme.serif(24)) }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.catalogAdmin && store.draftRevision != nil {
                        Button(publishing ? "Publishing…" : "Publish draft") { confirmPublish = true }.disabled(publishing)
                    }
                }
            }
            .confirmationDialog("Publish this recipe for everyone with access to its recipe set?", isPresented: $confirmPublish, titleVisibility: .visible) {
                Button("Publish recipe") { Task { publishing = true; await store.publishSelectedDraft(); publishing = false } }
            }
        }
        .onAppear {
            guard preparation == nil else { return }
            do { preparation = try store.preparation(for: recipe, servings: recipe.baseServings) }
            catch { preparationError = error.localizedDescription }
        }
        .onChange(of: store.preferences) { _, preferences in
            if let catalog = store.catalog {
                _ = updatePreparation { try $0.applySavedPreferences(preferences, catalog: catalog, at: Date()) }
            }
        }
    }

    private func updatePreparation(_ edit: (inout CookingSession) throws -> Void) -> Bool {
        guard var next = preparation else { return false }
        do { try edit(&next); preparation = next; return true }
        catch { store.error = error.localizedDescription; return false }
    }
}
