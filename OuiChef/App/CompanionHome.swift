import SwiftUI

struct CompanionHome: View {
    @Bindable var store: CompanionStore
    @State private var query = ""
    @State private var favorites = false
    @State private var archived = false
    @State private var source: String?
    @State private var preferences: PreferencePage?
    @State private var account = false
    @State private var chef = false
    @State private var selectedAttempt: CookAttempt?
    private var filtered: [CompanionRecipe] {
        store.recipes.filter { ($0.archived == true) == archived && (!favorites || $0.favorite) && (source == nil || $0.sourceName == source) &&
            (query.isEmpty || ($0.title + " " + $0.ingredients.map(\.name).joined(separator: " ")).localizedCaseInsensitiveContains(query)) }
    }
    private var title: String {
        switch store.tab {
        case .home: "What’s cooking?"
        case .cookbook: archived ? "Tucked away." : "Your cookbook."
        case .album: "Made by you."
        case .kitchen: "Your kitchen."
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Group {
                header
                if store.tab == .home || store.tab == .cookbook {
                    if store.tab == .home && query.isEmpty {
                        if let attempt = store.inProgress.first { resumeRow(attempt, prominent: true) }
                        importAction
                        Button { store.lastAnswer = nil; chef = true } label: { HStack(spacing: 10) { ChefMascot(size: 32); Text("A cooking question? Ask your chef").font(.caption); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }.frame(minHeight: 44) }.buttonStyle(.plain).accessibilityIdentifier("home-chef").rowSurface()
                    }
                    search
                    if store.tab == .home && query.isEmpty {
                        ForEach(store.imports.filter(\.running)) { item in
                            Button { store.focusedImportID = item.id; store.showImport = true } label: {
                                HStack(spacing: 14) { ProgressView(); VStack(alignment: .leading, spacing: 5) { Text(item.previewTitle ?? "Your recipe is coming together").font(.subheadline.weight(.medium)); Text(item.message).font(.caption).foregroundStyle(Theme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }
                            }.buttonStyle(.plain).accessibilityIdentifier("import-tile-\(item.id)")
                        }
                        if store.inProgress.count > 1 {
                            DisclosureGroup("Other unfinished cooks") {
                                ForEach(store.inProgress.dropFirst()) { attempt in resumeRow(attempt) }
                            }.font(.subheadline)
                        }
                    }
                    HStack {
                        Text(store.tab == .home ? "Recently saved" : "\(filtered.count) recipes").font(Theme.serif(24)).foregroundStyle(Theme.plum)
                        Spacer()
                        if store.tab == .home { Button("See all") { store.tab = .cookbook }.font(.subheadline) }
                        else {
                            Menu {
                                Toggle("Favorites only", isOn: $favorites)
                                Toggle("Show archived", isOn: $archived)
                                Picker("Source", selection: $source) {
                                    Text("All sources").tag(String?.none)
                                    ForEach(Array(Set(store.recipes.map(\.sourceName))).sorted(), id: \.self) { Text($0).tag(Optional($0)) }
                                }
                            } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("Filter recipes")
                        }
                    }
                    if filtered.isEmpty { emptyRecipes }
                    else {
                        ForEach(store.tab == .home && query.isEmpty ? Array(filtered.prefix(4)) : filtered) { recipe in
                            Button { store.selectedRecipe = recipe } label: { CookbookRow(recipe: recipe) }
                                .buttonStyle(.plain).accessibilityIdentifier("recipe-\(recipe.id)")
                        }
                    }
                } else if store.tab == .album { album }
                else { kitchen }
                if let notice = store.notice { Label(notice, systemImage: "icloud").font(.caption).foregroundStyle(Theme.muted) }
                }.rowSurface()
            }
            .listStyle(.plain).scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
            .listRowSpacing(18).environment(\.defaultMinListRowHeight, 0)
            .id(store.tab)
            .listRowSeparator(.hidden).background(Theme.cream).foregroundStyle(Theme.ink)
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            .toolbar(.hidden, for: .navigationBar).keyboardDone()
            .refreshable { store.sync() }
        }
        .onChange(of: store.tab) { _, _ in query = ""; favorites = false; archived = false; source = nil }
        .sheet(isPresented: $store.showImport) { CompanionImportView(store: store) }
        .sheet(item: $store.selectedRecipe) { recipe in CompanionRecipeView(store: store, recipe: recipe) }
        .sheet(item: $preferences) { page in CompanionPreferences(store: store, section: page) }
        .sheet(isPresented: $account) { AccountView() }
        .sheet(isPresented: $chef) {
            NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 24) {
                ChefMascot(size: 60)
                Text("A little kitchen help.").font(Theme.serif(33)).foregroundStyle(Theme.plum)
                Text("Techniques, substitutions, or where to start. Ask away.").font(.subheadline).foregroundStyle(Theme.muted)
                InlineChefQuestion(store: store)
                if let answer = store.lastAnswer { Text(answer).font(.body).lineSpacing(4) }
            }.padding(24) }.background(Theme.cream).toolbar { Button("Close") { chef = false } } }.presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedAttempt) { attempt in AttemptDetailView(store: store, attemptID: attempt.id) }
        .fullScreenCover(isPresented: $store.showCooking) { CompanionCookingView(store: store) }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionEyebrow(title: "Oui Chef")
                Spacer()
                if store.tab == .home { Text(greeting).font(.caption).foregroundStyle(Theme.muted) }
            }
            Text(title).font(Theme.serif(38)).foregroundStyle(Theme.plum).accessibilityAddTraits(.isHeader)
            Text(store.tab == .home ? "A recipe you love. A little guidance." : store.tab == .cookbook ? "Good recipes deserve to be cooked." : store.tab == .album ? "Your cooking memories, all in one place." : "Good food, your way.")
                .font(.subheadline).foregroundStyle(Theme.muted)
        }.padding(.top, 18).padding(.bottom, 8).rowSurface()
    }
    private var greeting: String {
        let name = AccountSession.shared.name.split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? "Welcome to your kitchen" : "Hello, \(name)"
    }
    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
            TextField("Search your recipes…", text: $query).submitLabel(.done)
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
        }.font(.subheadline).foregroundStyle(Theme.muted).padding(15).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14)).rowSurface()
    }
    private var importAction: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.inProgress.isEmpty {
                HStack(alignment: .center, spacing: 20) {
                    Text("From a saved idea\nto tonight’s dinner.").font(Theme.serif(29)).foregroundStyle(Theme.plum).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    Image("WelcomeFood").resizable().scaledToFill().frame(width: 100, height: 112).clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 14, bottomTrailingRadius: 40, topTrailingRadius: 14)).accessibilityHidden(true)
                }
            }
            Button { store.focusedImportID = nil; store.showImport = true } label: {
                HStack { Image(systemName: "plus"); Text("Import a recipe"); Spacer(); Image(systemName: "arrow.right") }.padding(.horizontal, 20)
            }.buttonStyle(FilledButton()).accessibilityIdentifier("import-recipe")
            if store.inProgress.isEmpty { Text("Paste a link or your own recipe text. We’ll help you cook it.").font(.caption).foregroundStyle(Theme.muted) }
        }.rowSurface()
    }
    private func resumeRow(_ attempt: CookAttempt, prominent: Bool = false) -> some View {
        Button { store.resume(attempt.id) } label: {
            VStack(alignment: .leading, spacing: 12) {
                if prominent { SectionEyebrow(title: attempt.isPreparing ? "Ready when you are" : "Continue cooking") }
                HStack(spacing: 16) {
                    RecipePhoto(recipe: attempt.recipe).frame(width: 78, height: 88).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(attempt.recipe.title).font(Theme.serif(23)).foregroundStyle(Theme.plum)
                        Text(attempt.isPreparing ? "Gather your ingredients" : "Step \(attempt.focusIndex + 1) of \(attempt.recipe.steps.count) · \(attempt.currentStep.stage)").font(.caption).foregroundStyle(Theme.muted)
                        Text(attempt.isPreparing ? "Continue preparation →" : "Resume cooking →").font(.subheadline.weight(.medium)).foregroundStyle(Theme.plum)
                    }
                    Spacer(minLength: 0)
                }
            }.padding(prominent ? 18 : 0).background(prominent ? Theme.blush.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("cook-\(attempt.id)").rowSurface()
            .disabled(store.deletingAttemptIDs.contains(attempt.id))
            .swipeActions { Button(role: .destructive) { Task { await store.deleteAttempt(attempt.id) } } label: { Label("Delete", systemImage: "trash") }.accessibilityIdentifier("delete-cook-\(attempt.id)") }
    }
    private var emptyRecipes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(query.isEmpty && !favorites && !archived ? "Your next favorite\nstarts with a recipe." : "Nothing here just yet.").font(Theme.serif(28)).foregroundStyle(Theme.plum)
            Text(query.isEmpty ? archived ? "Archived recipes will appear here. You can restore them anytime." : "Save a recipe from a website, a creator, or your own notes." : "Try a recipe name or an ingredient.").font(.subheadline).foregroundStyle(Theme.muted)
            if store.tab == .cookbook && !archived { Button("Import your first recipe") { store.focusedImportID = nil; store.showImport = true }.buttonStyle(FilledButton()) }
        }.padding(.vertical, 22).rowSurface()
    }
    @ViewBuilder private var album: some View {
        if store.history.isEmpty {
            VStack(spacing: 20) { ChefMascot(size: 76); Text("Every dish has a story.").font(Theme.serif(28)).foregroundStyle(Theme.plum); Text("Finish a recipe to begin yours. A photo is always optional.").font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center); Button("Find something to cook") { store.tab = .cookbook }.buttonStyle(FilledButton()) }.padding(.vertical, 45).rowSurface()
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 18)], spacing: 26) {
                ForEach(store.history) { attempt in Button { selectedAttempt = attempt } label: { AttemptTile(store: store, attempt: attempt) }.buttonStyle(.plain) }
            }.rowSurface()
        }
    }
    private var kitchen: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 16) { ChefMascot(size: 64); VStack(alignment: .leading, spacing: 5) { Text(AccountSession.shared.name).font(Theme.serif(26)).foregroundStyle(Theme.plum); Text("Your personal cooking companion").font(.caption).foregroundStyle(Theme.muted) } }
            HStack { stat(store.recipes.filter { $0.archived != true }.count, "Recipes"); Spacer(); stat(store.history.count, "Dishes made"); Spacer(); stat(store.recipes.filter { $0.favorite && $0.archived != true }.count, "Favorites") }.padding(.vertical, 20).overlay(alignment: .top) { Theme.line.frame(height: 1) }.overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
            VStack(spacing: 0) {
                kitchenRow("Cooking preferences", "Diet, allergies, and your tastes", "fork.knife") { preferences = .diet }
                kitchenRow("Kitchen defaults", "Servings, tools, and measurements", "frying.pan") { preferences = .kitchen }
                kitchenRow("Voice & language", "How your chef helps you", "mic") { preferences = .voice }
                kitchenRow("Import history", "Recipes you’ve brought into your kitchen", "link") { store.focusedImportID = nil; store.showImport = true }
                kitchenRow("Notifications", "Timers and gentle reminders", "bell") { preferences = .voice }
                kitchenRow("Privacy & account", "Your information and sign-in", "lock") { account = true }
            }
            ChefCallout(text: "A little more confidence.\nA little less looking at your phone.")
        }.rowSurface()
    }
    private func stat(_ count: Int, _ label: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text("\(count)").font(Theme.serif(30)).foregroundStyle(Theme.plum); Text(label).font(.caption).foregroundStyle(Theme.muted) } }
    private func kitchenRow(_ title: String, _ subtitle: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 16) { Image(systemName: symbol).font(.title3).foregroundStyle(Theme.plum).frame(width: 26); VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline.weight(.medium)); Text(subtitle).font(.caption).foregroundStyle(Theme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.plum) }.padding(.vertical, 17).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier(title)
    }
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.home, "house"); tabButton(.cookbook, "book.closed")
            Button { store.focusedImportID = nil; store.showImport = true } label: { Image(systemName: "plus").font(.system(size: 25, weight: .light)).foregroundStyle(.white).frame(width: 54, height: 54).background(Theme.plum, in: Circle()).frame(maxWidth: .infinity) }.accessibilityLabel("Import recipe")
            tabButton(.album, "photo.on.rectangle"); tabButton(.kitchen, "person.crop.circle")
        }.padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 7).background(Theme.cream).overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
    private func tabButton(_ tab: KitchenTab, _ symbol: String) -> some View {
        Button { store.tab = tab } label: { VStack(spacing: 5) { Image(systemName: symbol).font(.system(size: 20, weight: store.tab == tab ? .semibold : .regular)); Text(tab.rawValue).font(.caption2) }.foregroundStyle(store.tab == tab ? Theme.plum : Theme.muted).frame(maxWidth: .infinity, minHeight: 48) }.accessibilityAddTraits(store.tab == tab ? .isSelected : []).accessibilityIdentifier("tab-\(tab.rawValue)")
    }
}

struct CookbookRow: View {
    let recipe: CompanionRecipe
    var body: some View {
        HStack(spacing: 16) {
            RecipePhoto(recipe: recipe).frame(width: 94, height: 105).clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.title).font(Theme.serif(23)).foregroundStyle(Theme.plum).fixedSize(horizontal: false, vertical: true)
                Text([recipe.timeLabel, recipe.servings.map { "\($0) servings" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.muted)
                Text(recipe.sourceName).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if recipe.favorite { Image(systemName: "heart.fill").foregroundStyle(Theme.berry).accessibilityLabel("Favorite") }
        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).rowSurface()
    }
}

private extension View {
    func rowSurface() -> some View { listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24)).listRowSeparator(.hidden).listRowBackground(Color.clear) }
}
