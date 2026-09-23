import SwiftUI
import AuthenticationServices
import PhotosUI
import AVFoundation
import SafariServices
import FirebaseStorage
import FirebaseAuth

struct CompanionRootView: View {
    @State private var store = CompanionStore()
    @Bindable private var account = AccountSession.shared
    @Environment(\.scenePhase) private var phase
    private var preview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--companion-preview")
        #else
        false
        #endif
    }
    var body: some View {
        Group {
            if account.accountID == nil && !preview { CompanionWelcome() }
            else if store.loading { ZStack { Theme.cream.ignoresSafeArea(); ProgressView("Opening your kitchen…") } }
            else if !store.profile.onboardingComplete || store.profile.needsPreferenceReview { CompanionPreferences(store: store, onboarding: true) }
            else { CompanionHome(store: store) }
        }
        .id(account.accountID ?? "signed-out").tint(Theme.green).preferredColorScheme(.light)
        .task { store.switchAccount(account.accountID); account.onDeleteLocalAccount = { uid in try await store.deleteAccountData(uid) } }
        .onChange(of: account.accountID) { _, id in store.switchAccount(id) }
        .onChange(of: phase) { _, phase in
            if phase == .active { store.foreground = true; store.consumeSharedLinks(); store.sync() }
            else if phase == .background { store.background() }
            keepAwake()
        }
        .onChange(of: store.showCooking) { _, _ in keepAwake() }
        .onChange(of: store.profile.keepAwake) { _, _ in keepAwake() }
        .onChange(of: store.active?.finishedAt) { _, _ in keepAwake() }
        .alert("A little attention needed", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private func keepAwake() { UIApplication.shared.isIdleTimerDisabled = phase == .active && store.showCooking && store.active?.finishedAt == nil && store.profile.keepAwake }
}

private struct CompanionWelcome: View {
    @Bindable var account = AccountSession.shared
    @State private var email = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Image("WelcomeFood").resizable().scaledToFill().frame(width: geometry.size.width, height: max(360, geometry.size.height * 0.63)).clipped()
                        .overlay(LinearGradient(stops: [.init(color: Theme.cream.opacity(0.97), location: 0), .init(color: Theme.cream.opacity(0.9), location: 0.38), .init(color: Theme.cream.opacity(0.5), location: 0.55), .init(color: .clear, location: 0.72)], startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 18) {
                                Text("OUI CHEF").font(.system(size: 12, weight: .semibold)).tracking(4)
                                Text("A smarter\nway to cook.").font(Theme.serif(43)).lineSpacing(-2)
                                Text("Turn a recipe you love into\na little guidance in your kitchen.").font(.subheadline).lineSpacing(4)
                            }.padding(.horizontal, 30).padding(.top, 22).foregroundStyle(Theme.ink)
                        }
                    VStack(spacing: 14) {
                        Label("Good food brings us closer.", systemImage: "leaf").font(.caption).foregroundStyle(Theme.green).padding(.bottom, 6)
                        SignInWithAppleButton(.continue) { account.prepareApple($0) } onCompletion: { result in Task { await account.completeApple(result, intent: .signIn) } }
                            .signInWithAppleButtonStyle(.black).frame(height: 50).clipShape(Capsule()).disabled(account.busy)
                        Button { Task { await account.google(intent: .signIn) } } label: { Text("Continue with Google").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(16).overlay(Capsule().stroke(Theme.green.opacity(0.25))) }.disabled(account.busy)
                        Button("Sign up or sign in with email") { email = true }.font(.subheadline).frame(minHeight: 44)
                        if account.busy { ProgressView() }
                        if let error = account.error { Text(error).font(.caption).foregroundStyle(.red) }
                    }.padding(24).frame(maxWidth: .infinity).background(Theme.cream, in: UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34)).padding(.top, -26)
                }
            }.background(Theme.cream).ignoresSafeArea(edges: .bottom)
        }.sheet(isPresented: $email) { AccountView(emailOnly: true) }
    }
}

struct CompanionPreferences: View {
    let store: CompanionStore
    var onboarding = false
    @State private var draft = CookProfile()
    @State private var page = 0
    @State private var picker: PreferenceSection?
    @Environment(\.dismiss) private var dismiss
    private let diets = [("Everything", "A little of everything", "fork.knife"), ("Vegetarian", "Plants, dairy & eggs", "carrot"), ("Vegan", "Entirely plant based", "leaf"), ("Pescatarian", "Plants & seafood", "fish")]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if onboarding {
                        HStack { Text("\(page + 1) of 3"); Spacer(); if !draft.needsPreferenceReview { Button("Set up later") { finish() } } }.font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: Double(page + 1), total: 3).tint(Theme.green)
                    }
                    Text(onboarding ? ["What’s your\ncooking style?", "Make it\nyour own.", "A little about\nyour kitchen."][page] : "Your kitchen,\nyour way.").font(Theme.serif(38))
                    Text("A few preferences help your chef guide you. You can change them anytime.").font(.subheadline).foregroundStyle(.secondary)
                    if draft.needsPreferenceReview {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Review your saved preferences").font(.headline)
                            Text("Choose the matching options below. Saving replaces these earlier notes; nothing is changed until then.").font(.caption)
                            ForEach(draft.previousPreferencesPendingReview.keys.sorted(), id: \.self) { key in
                                Text("\(key.capitalized): \(draft.previousPreferencesPendingReview[key] ?? "")").font(.subheadline)
                            }
                        }.kitchenCard()
                    }
                    if !onboarding || page == 0 {
                        VStack(spacing: 8) {
                            ForEach(diets, id: \.0) { item in
                                Button { draft.diet = item.0 } label: {
                                    HStack(spacing: 16) {
                                        Image(systemName: item.2).font(.system(size: 26, weight: .light)).frame(width: 38).foregroundStyle(Theme.green)
                                        VStack(alignment: .leading, spacing: 5) { Text(item.0).font(.body); Text(item.1).font(.caption).foregroundStyle(.secondary) }
                                        Spacer(); Image(systemName: draft.diet == item.0 ? "checkmark.circle.fill" : "circle").foregroundStyle(draft.diet == item.0 ? Theme.green : Theme.green.opacity(0.3))
                                    }.padding(15).background(draft.diet == item.0 ? Theme.sage.opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: 16))
                                }.buttonStyle(.plain)
                            }
                        }
                        selectionRow(.allergies)
                        selectionRow(.restrictions)
                        Text("Your allergy settings are always controlled by you.").font(.caption).foregroundStyle(.secondary)
                    }
                    if !onboarding || page == 1 {
                        selectionRow(.dislikes)
                        choice("Spice", value: $draft.spice, options: ["Mild", "Medium", "Hot"])
                        choice("Salt", value: $draft.salt, options: ["Lower", "Balanced"])
                        choice("Cooking experience", value: $draft.experience, options: ["Beginner", "Home cook", "Confident"])
                    }
                    if !onboarding || page == 2 {
                        Stepper("Usually cooking for \(draft.servings)", value: $draft.servings, in: 1...20)
                        Stepper("Household size: \(draft.householdSize)", value: $draft.householdSize, in: 1...20)
                        choice("Measurements", value: $draft.units, options: ["Metric", "US customary"])
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recipe and chef language").font(.subheadline.weight(.medium))
                            TextField("For example, English or Mandarin", text: $draft.voiceLanguage)
                                .textInputAutocapitalization(.words).padding(14)
                                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityIdentifier("voice-language")
                                .onChange(of: draft.voiceLanguage) { _, value in draft.voiceLanguage = String(value.prefix(80)) }
                            Text("New recipes, transcripts, and your chef use this language, whatever language the source uses.").font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("Keep screen awake while cooking", isOn: $draft.keepAwake)
                        Toggle("Gentle cooking reminders", isOn: $draft.gentleGuidance)
                        DisclosureGroup("Equipment · optional") {
                            selectionRow(.equipment).padding(.top, 15)
                        }.font(.subheadline)
                    }
                }.padding(26)
            }.background(Theme.cream).foregroundStyle(Theme.ink)
                .safeAreaInset(edge: .bottom) {
                    Button(onboarding && page < 2 ? "Next" : draft.needsPreferenceReview ? "Save reviewed preferences" : onboarding ? "Open my kitchen" : "Save preferences") {
                        if onboarding && page < 2 { withAnimation { page += 1 } } else { finish() }
                    }.buttonStyle(FilledButton()).padding(.horizontal, 26).padding(.vertical, 12).background(Theme.cream)
                }
                .toolbar { if !onboarding { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } } }
        }.onAppear { draft = store.profile }
        .sheet(item: $picker) { section in PreferenceChecklist(section: section, profile: $draft) }
    }
    private func finish() {
        draft.voiceLanguage = draft.voiceLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.voiceLanguage.isEmpty { draft.voiceLanguage = "English" }
        draft.onboardingComplete = true
        draft.previousPreferencesPendingReview = [:]
        store.setProfile(draft); dismiss()
    }
    private func selectionRow(_ section: PreferenceSection) -> some View {
        let names = section.names(draft.selectedIDs(section))
        let empty = section == .allergies ? (draft.allergyStatus == .noneKnown ? "No known allergies" : "Not specified") : "Choose options"
        return Button { picker = section } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title).font(.subheadline.weight(.medium))
                    Text(names.isEmpty ? empty : names.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.green)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier("preferences-" + section.rawValue)
    }
    private func choice(_ title: String, value: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.subheadline.weight(.medium)); Picker(title, selection: value) { ForEach(options, id: \.self) { Text($0) } }.pickerStyle(.segmented) }
    }
}

struct CompanionHome: View {
    @Bindable var store: CompanionStore
    @State private var tab = "Home"
    @State private var query = ""
    @State private var favorites = false
    @State private var settings = false
    @State private var account = false
    @State private var selectedAttempt: CookAttempt?
    private var pendingImports: [RecipeImport] {
        store.imports.filter { item in
            item.status != "canceled" && !store.recipes.contains(where: { $0.id == (item.recipeID ?? item.id) }) && !favorites &&
            (query.isEmpty || ((item.previewTitle ?? "") + " " + item.source).localizedCaseInsensitiveContains(query))
        }
    }
    private var filtered: [CompanionRecipe] { store.recipes.filter { (!favorites || $0.favorite) && (query.isEmpty || ($0.title + " " + $0.ingredients.map(\.name).joined(separator: " ")).localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 27) {
                    header
                    if tab == "Profile" { profileContent }
                    else if tab == "Album" { album }
                    else {
                        search
                        if tab == "Home" && query.isEmpty {
                            importCard
                            if !store.inProgress.isEmpty { inProgress }
                            if !store.history.isEmpty { recentDishes }
                        }
                        HStack {
                            Text(tab == "Cookbook" ? "Your recipes" : "Saved for a good day").font(Theme.serif(25))
                            Spacer()
                            Button { favorites.toggle() } label: { Image(systemName: favorites ? "heart.fill" : "heart").frame(width: 44, height: 44) }.accessibilityLabel(favorites ? "Show all recipes" : "Show favorites")
                        }
                        if filtered.isEmpty && pendingImports.isEmpty {
                            if query.isEmpty && !favorites { emptyCookbook }
                            else { ContentUnavailableView.search(text: query.isEmpty ? "Favorites" : query) }
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 24) {
                                ForEach(pendingImports) { item in
                                    Button { store.focusedImportID = item.id; store.showImport = true } label: {
                                        ImportRecipePreview(item: item, compact: true)
                                    }.buttonStyle(.plain).accessibilityIdentifier("import-tile-\(item.id)")
                                }
                                ForEach(filtered) { recipe in
                                    Button { store.selectedRecipe = recipe } label: { RecipeTile(recipe: recipe) }.buttonStyle(.plain).accessibilityIdentifier("recipe-\(recipe.id)")
                                }
                            }
                        }
                    }
                    if let notice = store.notice { Label(notice, systemImage: "icloud").font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
            }.background(Theme.cream).foregroundStyle(Theme.ink).keyboardDone()
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
                .toolbar(.hidden, for: .navigationBar)
                .refreshable { store.sync() }
        }
        .sheet(isPresented: $store.showImport) { CompanionImportView(store: store) }
        .sheet(item: $store.selectedRecipe) { recipe in CompanionRecipeView(store: store, recipe: recipe) }
        .sheet(isPresented: $settings) { CompanionPreferences(store: store) }
        .sheet(isPresented: $account) { AccountView() }
        .sheet(item: $selectedAttempt) { attempt in AttemptDetailView(store: store, attemptID: attempt.id) }
        .fullScreenCover(isPresented: $store.showCooking) { CompanionCookingView(store: store) }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tab == "Home" ? "A LITTLE HELP IN THE KITCHEN" : "OUI CHEF").font(.system(size: 10, weight: .semibold)).tracking(2.5).foregroundStyle(Theme.green)
                Text(tab == "Home" ? "What shall we\ncook today?" : tab == "Album" ? "Made by you." : tab == "Profile" ? "Your kitchen." : "Your cookbook.").font(Theme.serif(37)).lineSpacing(-1)
                if tab == "Album" { Text("Every dish has a little story.").font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Button { settings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("Cooking preferences")
        }
    }
    private var search: some View {
        HStack(spacing: 10) { Image(systemName: "magnifyingglass"); TextField("Search your recipes…", text: $query).submitLabel(.done); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") } }
            .font(.subheadline).foregroundStyle(.secondary).padding(14).background(Theme.green.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
    }
    private var importCard: some View {
        Button { store.focusedImportID = nil; store.showImport = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "plus").font(.title3).foregroundStyle(.white).frame(width: 42, height: 42).background(Theme.green, in: Circle())
                VStack(alignment: .leading, spacing: 6) { Text("Found something delicious?").font(.body.weight(.medium)); Text("Bring a recipe from anywhere.").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "arrow.up.right").font(.subheadline)
            }.padding(19).background(Theme.sage, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("import-recipe")
    }
    private var emptyCookbook: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image("WelcomeFood").resizable().scaledToFill().frame(height: 190).clipped().clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
            Text("Your next favorite\nstarts with a link.").font(Theme.serif(28))
            Text("Save that pasta you saw, the bread you’ve been meaning to try, or a family favorite from the web.").font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            Button("Import your first recipe") { store.focusedImportID = nil; store.showImport = true }.buttonStyle(FilledButton())
        }
    }
    private var inProgress: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("On the go").font(Theme.serif(25))
            ForEach(store.inProgress) { attempt in
                Button { store.resume(attempt.id) } label: {
                    HStack(spacing: 14) {
                        RecipePhoto(recipe: attempt.recipe).frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 7) { Text(attempt.recipe.title).font(.subheadline.weight(.medium)); Text("Step \(attempt.focusIndex + 1) of \(attempt.recipe.steps.count) · \(attempt.currentStep.stage)").font(.caption).foregroundStyle(.secondary); Text("Continue cooking →").font(.caption.weight(.medium)).foregroundStyle(Theme.green) }
                        Spacer()
                    }.padding(12).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            }
        }
    }
    private var recentDishes: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Recently cooked").font(Theme.serif(25)); Spacer(); Button("See all") { tab = "Album" }.font(.caption) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) { ForEach(store.history.prefix(6)) { attempt in Button { selectedAttempt = attempt } label: { AttemptTile(store: store, attempt: attempt).frame(width: 165) }.buttonStyle(.plain) } }
            }
        }
    }
    private var album: some View {
        Group {
            if store.history.isEmpty {
                VStack(spacing: 18) { Image(systemName: "camera.macro").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(Theme.green); Text("Your kitchen memories\nbegin here.").font(Theme.serif(29)).multilineTextAlignment(.center); Text("Finish a recipe to save your first cooking story. Photos are always optional.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center); Button("Find something to cook") { tab = "Cookbook" }.buttonStyle(FilledButton()) }.padding(.vertical, 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 26) { ForEach(store.history) { attempt in Button { selectedAttempt = attempt } label: { AttemptTile(store: store, attempt: attempt) }.buttonStyle(.plain) } }
            }
        }
    }
    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 15) { Image(systemName: "person.crop.circle").font(.system(size: 42, weight: .light)); VStack(alignment: .leading, spacing: 6) { Text(AccountSession.shared.name).font(.headline); Text("Your private cookbook & album").font(.caption).foregroundStyle(.secondary) } }
            HStack { stat("\(store.recipes.count)", "recipes"); Spacer(); stat("\(store.history.count)", "dishes made"); Spacer(); stat("\(store.recipes.filter(\.favorite).count)", "favorites") }.padding(22).background(Theme.sage, in: RoundedRectangle(cornerRadius: 20))
            Button { settings = true } label: { Label("Cooking preferences", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, minHeight: 48, alignment: .leading) }
            Button { store.focusedImportID = nil; store.showImport = true } label: { Label("Import history", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 48, alignment: .leading) }
            Button { account = true } label: { Label("Privacy & account", systemImage: "person.crop.circle").frame(maxWidth: .infinity, minHeight: 48, alignment: .leading) }
            Text("A little more confidence.\nA little less looking at your phone.").font(Theme.serif(25)).foregroundStyle(Theme.green).padding(.top, 30)
        }
    }
    private func stat(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(value).font(Theme.serif(30)); Text(label).font(.caption).foregroundStyle(.secondary) } }
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("Home", "house"); tabButton("Cookbook", "book.closed")
            Button { store.focusedImportID = nil; store.showImport = true } label: { Image(systemName: "plus").font(.system(size: 22)).foregroundStyle(.white).frame(width: 48, height: 48).background(Theme.ink, in: Circle()).frame(maxWidth: .infinity) }.accessibilityLabel("Import recipe")
            tabButton("Album", "photo.on.rectangle"); tabButton("Profile", "person")
        }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 8).background(Theme.cream).overlay(alignment: .top) { Theme.green.opacity(0.1).frame(height: 1) }
    }
    private func tabButton(_ name: String, _ symbol: String) -> some View {
        Button { tab = name; query = ""; favorites = false } label: { VStack(spacing: 6) { Image(systemName: symbol).font(.system(size: 19, weight: tab == name ? .semibold : .regular)); Text(name).font(.system(size: 10)) }.foregroundStyle(tab == name ? Theme.ink : .secondary).frame(maxWidth: .infinity, minHeight: 48) }.accessibilityAddTraits(tab == name ? .isSelected : []).accessibilityIdentifier("tab-\(name)")
    }
}

struct RecipePhoto: View {
    let recipe: CompanionRecipe
    @State private var downloaded: UIImage?
    var body: some View {
        GeometryReader { geometry in
            Group {
                if recipe.id == "preview-pasta" { Image("WelcomeFood").resizable().scaledToFill() }
                else if let downloaded { Image(uiImage: downloaded).resizable().scaledToFill() } else { placeholder }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityLabel(recipe.title).task(id: recipe.imagePath) {
            guard let uid = Auth.auth().currentUser?.uid, let path = recipe.imagePath, path.hasPrefix("users/\(uid)/recipeMedia/\(recipe.id)/cover-") else { return }
            if let data = try? await Storage.storage().reference().child(path).data(maxSize: 2_000_000), Auth.auth().currentUser?.uid == uid { downloaded = UIImage(data: data) }
        }
    }
    private var placeholder: some View {
        ZStack { Theme.sage; Image(systemName: "fork.knife").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Theme.green.opacity(0.6)) }
    }
}
private struct RecipeTile: View {
    let recipe: CompanionRecipe
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RecipePhoto(recipe: recipe).frame(height: 155).clipShape(RoundedRectangle(cornerRadius: 17)).overlay(alignment: .topTrailing) { if recipe.favorite { Image(systemName: "heart.fill").font(.caption).padding(9).background(Theme.cream, in: Circle()).padding(8) } }
            Text(recipe.title).font(Theme.serif(20)).lineLimit(2).multilineTextAlignment(.leading)
            Text(recipe.timeLabel + " · " + recipe.sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if !recipe.reviewed { Text("READY TO REVIEW").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Theme.green) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ImportRecipePreview: View {
    let item: RecipeImport
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if compact {
                RoundedRectangle(cornerRadius: 17).fill(Theme.sage.opacity(0.6)).frame(height: 155)
                    .overlay { if item.running { ProgressView() } else { Image(systemName: "info.circle").foregroundStyle(Theme.green) } }
                    .accessibilityHidden(true)
            }
            Text(item.previewTitle ?? "Your recipe").font(Theme.serif(compact ? 20 : 25)).lineLimit(compact ? 2 : nil)
                .redacted(reason: item.previewTitle == nil && item.running ? .placeholder : [])
            if let creator = item.previewCreator { Text(creator).font(.caption).foregroundStyle(.secondary) }
            if compact {
                Text(item.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            } else {
                if let summary = item.previewSummary { Text(summary).font(.subheadline).foregroundStyle(.secondary) }
                previewSection("Ingredients", lines: item.previewIngredients)
                previewSection("Cooking steps", lines: item.previewSteps)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
    }
    private func previewSection(_ title: String, lines: [String]?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if let lines {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in Text(line).font(.subheadline) }
            } else if item.running {
                Text("Recipe details are on their way\nA little more to come\nPutting everything together").font(.subheadline).lineSpacing(10)
                    .redacted(reason: .placeholder).accessibilityLabel("\(title) are loading")
            } else { Text("Not available yet").font(.subheadline).foregroundStyle(.secondary) }
        }.padding(.vertical, 8)
    }
}

struct CompanionImportView: View {
    @Bindable var store: CompanionStore
    @State private var url = ""
    @State private var recipeText = ""
    @State private var textMode = false
    private var focusedImport: RecipeImport? { store.imports.first { $0.id == store.focusedImportID } }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    if let item = focusedImport {
                        Text(item.status == "ready" ? "Your recipe is ready." : item.running ? "Your recipe is\ncoming together." : "Let’s try that again.").font(Theme.serif(37))
                        importRow(item)
                        ImportRecipePreview(item: item)
                        if !item.running {
                            Button("Import another recipe") { store.focusedImportID = nil; url = ""; recipeText = "" }.font(.subheadline)
                        }
                    } else {
                        Text("Turn any recipe\ninto your recipe.").font(Theme.serif(37))
                        Text("Bring the ingredients and instructions. Your chef will turn them into a recipe you can cook.").font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                        VStack(alignment: .leading, spacing: 14) {
                            Text(textMode ? "Paste the text" : "Paste a link").font(.headline)
                            if textMode {
                                TextEditor(text: $recipeText).frame(height: 160).padding(10).scrollContentBackground(.hidden)
                                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                                    .accessibilityLabel("Recipe text").accessibilityIdentifier("recipe-text")
                                Text("Include ingredients and steps. A link isn’t required.").font(.caption).foregroundStyle(.secondary)
                            } else {
                                HStack(spacing: 12) {
                                    Image(systemName: "link")
                                    TextField("Paste a link here…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("recipe-url")
                                    PasteButton(payloadType: String.self) { values in if let first = values.first { url = first } }.labelStyle(.iconOnly)
                                }.padding(15).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                            }
                            Button {
                                dismissCookingKeyboard()
                                Task { await store.importRecipe(textMode ? "" : url, text: textMode ? recipeText : "") }
                            } label: {
                                HStack(spacing: 12) {
                                    if store.importing { ProgressView().tint(.white) }
                                    Text(store.importing ? "Adding your recipe…" : "Make it a recipe")
                                    Image(systemName: "arrow.right")
                                }.padding(.horizontal, 20).frame(minHeight: 24)
                            }.buttonStyle(FilledButton()).accessibilityIdentifier("make-recipe")
                                .disabled((textMode ? recipeText : url).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.importing)
                        }
                        HStack { Rectangle().frame(height: 1); Text("or").font(.caption); Rectangle().frame(height: 1) }.foregroundStyle(Theme.green.opacity(0.3))
                        VStack(spacing: 12) {
                            HStack(spacing: 14) {
                                Image(systemName: "photo").frame(width: 24)
                                Text("Upload a photo")
                                Spacer()
                                Text("Coming soon").font(.caption).foregroundStyle(.secondary)
                            }.padding(18).background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityElement(children: .combine)
                            Button { dismissCookingKeyboard(); textMode.toggle() } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: textMode ? "link" : "doc.text").frame(width: 24)
                                    Text(textMode ? "Paste a link" : "Paste the text")
                                    Spacer(); Image(systemName: "chevron.right").font(.caption)
                                }.padding(18).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityIdentifier("toggle-import-mode").disabled(store.importing)
                        }
                        Label("Or tap Share in another app, then choose Oui Chef. Look under More if you don’t see it.", systemImage: "square.and.arrow.up").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                    }
                    if focusedImport == nil && !store.imports.isEmpty {
                        Divider().padding(.vertical, 8)
                        Text("In your kitchen").font(Theme.serif(25))
                        ForEach(store.imports) { item in
                            Button { store.focusedImportID = item.id } label: {
                                HStack { Text(item.previewTitle ?? item.source); Spacer(); Text(item.status.capitalized).font(.caption); Image(systemName: "chevron.right") }
                                    .padding(16).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(25)
            }.background(Theme.cream).foregroundStyle(Theme.ink).keyboardDone()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.onAppear { url = store.pendingURL }
    }
    private func importRow(_ item: RecipeImport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(item.source).font(.headline); Spacer(); if item.running { ProgressView() } else { Image(systemName: item.status == "ready" ? "checkmark.circle.fill" : "info.circle").foregroundStyle(Theme.green) } }
            Text(item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if item.running {
                ForEach(Array(RecipeImport.stages.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 12) {
                        if index < item.progressStage { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green) }
                        else if index == item.progressStage { ProgressView().controlSize(.small) }
                        else { Image(systemName: "circle").foregroundStyle(Theme.green.opacity(0.25)) }
                        Text(label).font(.subheadline).foregroundStyle(index <= item.progressStage ? Theme.ink : .secondary)
                    }.accessibilityElement(children: .combine)
                        .accessibilityLabel("\(label): \(index < item.progressStage ? "Complete" : index == item.progressStage ? "In progress" : "Waiting")")
                }
            }
            Text(item.message).font(.subheadline).foregroundStyle(.secondary)
            if item.hasImportEvidence {
                Divider()
                Text("Import evidence").font(.headline)
                evidenceValue("Source title", item.sourceTitle)
                evidenceValue("Recipe title", item.recipeTitle)
                evidenceValue("Creator", item.previewCreator)
                evidenceValue("Source reader", item.sourceExtractor)
                if let duration = item.sourceDurationSeconds { evidenceValue("Video duration", "\(Int(duration.rounded())) seconds") }
                if let point = item.failurePoint { evidenceValue("Last incomplete stage", point) }
                if let reason = item.extractionReason { evidenceValue("Parser result", reason) }
                if let seconds = item.frameSeconds, !seconds.isEmpty { evidenceValue("Frames sampled", seconds.map { "\(Int($0.rounded()))s" }.joined(separator: ", ")) }
                evidenceDisclosure("Ingredients captured", text: item.previewIngredients?.joined(separator: "\n"), identifier: "import-ingredients")
                evidenceDisclosure("Original transcript\(item.transcriptLanguage.map { " · \($0)" } ?? "")", text: item.originalTranscript, identifier: "original-transcript")
                evidenceDisclosure("Translated transcript", text: item.translatedTranscript, identifier: "translated-transcript")
                evidenceDisclosure("Video observations", text: item.videoObservations, identifier: "video-observations")
            }
            if item.status == "ready", let recipe = store.recipes.first(where: { $0.id == item.recipeID }) {
                Button("Review \(recipe.title) →") { dismiss(); Task { try? await Task.sleep(for: .milliseconds(400)); store.selectedRecipe = recipe } }.font(.subheadline.weight(.medium))
            } else if item.running {
                HStack { Text("You can leave. We’ll keep working.").font(.caption); Spacer(); Button("Cancel") { Task { await store.cancelImport(item.id) } }.font(.caption) }
            } else if ["failed","skipped","canceled"].contains(item.status) {
                Button("Try again or paste recipe text") { url = item.url; textMode = item.url.isEmpty; store.focusedImportID = nil }.font(.subheadline)
            }
        }.padding(19).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
    }
    @ViewBuilder private func evidenceValue(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.subheadline).textSelection(.enabled)
            }
        }
    }
    @ViewBuilder private func evidenceDisclosure(_ label: String, text: String?, identifier: String) -> some View {
        if let text, !text.isEmpty {
            DisclosureGroup(label) { Text(text).font(.caption).padding(.top, 8).textSelection(.enabled) }
                .font(.subheadline.weight(.medium)).accessibilityIdentifier(identifier)
        }
    }
}

struct CompanionRecipeView: View {
    @Bindable var store: CompanionStore
    @State var recipe: CompanionRecipe
    @State private var tab = "Ingredients"
    @State private var preparation = false
    @State private var checked: Set<String> = []
    @State private var questions = false
    @State private var acceptedWarnings = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    if preparation {
                        Text("Let’s get ready.").font(Theme.serif(37)).padding(.top, 15)
                        Text("Gather the key ingredients. Check off what you have, or go straight to cooking.").font(.subheadline).foregroundStyle(.secondary)
                        ingredientList(recipe.ingredients.filter { !$0.pantry })
                        if !recipe.preparation.isEmpty { preparationList }
                    } else {
                        RecipePhoto(recipe: recipe).frame(height: 265).clipShape(RoundedRectangle(cornerRadius: 25))
                        VStack(alignment: .leading, spacing: 10) {
                            Text(recipe.title).font(Theme.serif(35)).fixedSize(horizontal: false, vertical: true)
                            if !recipe.summary.isEmpty { Text(recipe.summary).font(.subheadline).foregroundStyle(.secondary) }
                            HStack(spacing: 8) {
                                Image(systemName: "link"); Text(recipe.creator ?? recipe.sourceName)
                                if let source = URL(string: recipe.sourceURL), ["https", "http"].contains(source.scheme ?? "") { Text("·"); Link("Original recipe ↗", destination: source) }
                            }.font(.caption).foregroundStyle(Theme.green)
                        }
                        HStack(spacing: 20) {
                            Label(recipe.servings.map { "\($0) servings" } ?? "Servings not specified", systemImage: "person.2")
                            Label(recipe.timeLabel, systemImage: "clock")
                        }.font(.caption).padding(.vertical, 7)
                        HStack(spacing: 25) { ForEach(["Ingredients", "Steps", "Notes"], id: \.self) { name in Button { tab = name } label: { Text(name).font(.subheadline).foregroundStyle(tab == name ? Theme.ink : .secondary).padding(.vertical, 12).overlay(alignment: .bottom) { if tab == name { Theme.green.frame(height: 1.5) } } } } }
                        if tab == "Ingredients" {
                            Text("Key ingredients").font(Theme.serif(24))
                            ingredientList(recipe.ingredients.filter { !$0.pantry })
                            if recipe.ingredients.contains(where: \.pantry) { DisclosureGroup("Pantry basics (\(recipe.ingredients.filter(\.pantry).count))") { ingredientList(recipe.ingredients.filter(\.pantry)).padding(.top, 12) }.font(.subheadline) }
                            if !recipe.preparation.isEmpty { preparationList }
                            if !recipe.equipment.isEmpty { DisclosureGroup("Equipment · optional") { Text(recipe.equipment.joined(separator: ", ")).font(.subheadline).padding(.vertical, 10) } }
                        } else if tab == "Steps" {
                            ForEach(recipe.stages, id: \.self) { stage in
                                VStack(alignment: .leading, spacing: 17) {
                                    Text(stage).font(Theme.serif(25))
                                    ForEach(recipe.steps.filter { $0.stage == stage }) { step in
                                        VStack(alignment: .leading, spacing: 9) {
                                            Text("\((recipe.steps.firstIndex(of: step) ?? 0) + 1). \(step.title)").font(.headline)
                                            Text(step.instruction).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                                            if let cue = step.visualCue { Label(cue, systemImage: "eye").font(.caption).foregroundStyle(Theme.green) }
                                            if let duration = step.durationSeconds { Label("\(Int(duration / 60)) min\(step.timingEstimated ? " · estimated" : "")", systemImage: "timer").font(.caption) }
                                            if let temperature = step.temperature { Label(temperature, systemImage: "thermometer.medium").font(.caption) }
                                        }.padding(.bottom, 6)
                                    }
                                }
                            }
                        } else { notes }
                    }
                    if !recipe.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Before you cook", systemImage: "exclamationmark.circle").font(.headline)
                            ForEach(recipe.warnings, id: \.self) { Text($0).font(.subheadline) }
                            if preparation { Toggle("I’ve reviewed these notes", isOn: $acceptedWarnings).font(.subheadline) }
                        }.padding(18).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button { questions = true } label: { HStack { Image(systemName: "sparkles"); Text("Can I use something else?"); Spacer(); Image(systemName: "mic") }.font(.subheadline).padding(17).background(Theme.sage, in: RoundedRectangle(cornerRadius: 15)) }.buttonStyle(.plain)
                    if !store.history.filter({ $0.recipe.id == recipe.id }).isEmpty {
                        Text("Made before").font(Theme.serif(25))
                        ForEach(store.history.filter { $0.recipe.id == recipe.id }) { attempt in
                            VStack(alignment: .leading, spacing: 6) { Text(Date(timeIntervalSince1970: (attempt.finishedAt ?? 0) / 1000), style: .date).font(.subheadline.weight(.medium)); if !attempt.changes.isEmpty { Text(attempt.changes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) } }
                        }
                    }
                }.padding(24)
            }.background(Theme.cream).foregroundStyle(Theme.ink)
            .safeAreaInset(edge: .bottom) {
                Button(preparation ? "Let’s cook" : recipe.reviewed ? "Start cooking" : "Save to my cookbook") {
                    if preparation { store.start(recipe); dismiss(); Task { await store.enableNotifications() } }
                    else if !recipe.reviewed { recipe.reviewed = true; store.saveRecipe(recipe) }
                    else { withAnimation { preparation = true } }
                }.buttonStyle(FilledButton()).disabled(preparation && !recipe.warnings.isEmpty && !acceptedWarnings).padding(.horizontal, 24).padding(.vertical, 12).background(Theme.cream)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { if preparation { preparation = false } else { dismiss() } } label: { Image(systemName: "arrow.left") }.accessibilityLabel("Back") }
                ToolbarItem(placement: .topBarTrailing) { Button { recipe.favorite.toggle(); store.saveRecipe(recipe) } label: { Image(systemName: recipe.favorite ? "heart.fill" : "heart") }.accessibilityLabel("Favorite recipe") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete recipe").accessibilityIdentifier("delete-recipe")
                }
            }
            .disabled(store.deletingRecipeIDs.contains(recipe.id))
            .alert("Delete \(recipe.title)?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete recipe", role: .destructive) { Task { await store.deleteRecipe(recipe.id) } }
            } message: { Text("This removes the recipe from your cookbook. Your cooking history and photos are kept.") }
        }.sheet(isPresented: $questions) { RecipeQuestionView(store: store, recipe: recipe) }
    }
    private func ingredientList(_ values: [RecipeIngredient]) -> some View {
        VStack(spacing: 17) {
            ForEach(values) { item in
                HStack(spacing: 14) {
                    Image(systemName: ingredientSymbol(item.name)).font(.system(size: 25, weight: .light)).foregroundStyle(Theme.green).frame(width: 42, height: 42).background(Theme.sage.opacity(0.6), in: Circle()).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) { Text(item.name).font(.subheadline.weight(.medium)); Text(item.quantity + (item.optional ? " · optional" : "")).font(.caption).foregroundStyle(.secondary); if item.component != "Main" { Text(item.component).font(.caption2).foregroundStyle(Theme.green) }; if item.origin == "inferred" { Text("Estimated").font(.caption2).foregroundStyle(Theme.green) } }
                    Spacer()
                    if preparation { Button { if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) } } label: { Image(systemName: checked.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.green).frame(width: 44, height: 44) }.accessibilityLabel("\(checked.contains(item.id) ? "Uncheck" : "Check") \(item.name)") }
                }
            }
        }
    }
    private var preparationList: some View {
        VStack(alignment: .leading, spacing: 12) { Text("Before you begin").font(Theme.serif(25)); ForEach(recipe.preparation, id: \.self) { text in Label(text, systemImage: "checkmark").font(.subheadline).foregroundStyle(.secondary) } }
    }
    private var notes: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !recipe.adaptations.isEmpty { Text("For your kitchen").font(Theme.serif(25)); ForEach(recipe.adaptations, id: \.self) { Text($0).font(.subheadline) } }
            ForEach(recipe.ingredients.filter { $0.substitution != nil }) { item in VStack(alignment: .leading, spacing: 6) { Text("Instead of \(item.name)").font(.headline); Text(item.substitution ?? "").font(.subheadline).foregroundStyle(.secondary) } }
            ForEach(recipe.notes, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
            if recipe.notes.isEmpty && recipe.adaptations.isEmpty { Text("Ask your chef about substitutions or anything you’re unsure of.").font(.subheadline).foregroundStyle(.secondary) }
            if !recipe.evidence.isEmpty { DisclosureGroup("From the source & estimated details") { ForEach(Array(recipe.evidence.enumerated()), id: \.offset) { _, evidence in VStack(alignment: .leading, spacing: 5) { Text(evidence.origin == "source" ? "From the creator" : evidence.origin == "inferred" ? "Estimated" : "Supporting source").font(.caption.weight(.semibold)); Text(evidence.detail).font(.caption); if let raw = evidence.url, let url = URL(string: raw), url.scheme == "https" { Link("View source", destination: url).font(.caption) } }.padding(.vertical, 6) } } }
        }
    }
}

struct CompanionCookingView: View {
    @Bindable var store: CompanionStore
    @State private var showSteps = false
    @State private var showQuestions = false
    @State private var timerEntry = false
    @State private var timerMinutes = "10"
    @State private var changeEntry = false
    @State private var changeText = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let attempt = store.active {
                    if attempt.finishedAt != nil { CompanionCompletion(store: store, attempt: attempt) }
                    else { cooking(attempt) }
                } else { ContentUnavailableView("Choose a recipe", systemImage: "book.closed") }
            }.background(Theme.cream).foregroundStyle(Theme.ink)
                .toolbar(.hidden, for: .navigationBar)
        }
        .onDisappear { store.stopVoice() }
        .sheet(isPresented: $showQuestions) { if let recipe = store.active?.recipe { RecipeQuestionView(store: store, recipe: recipe) } }
        .sheet(isPresented: $showSteps) { stepsSheet }
        .sheet(isPresented: $store.showPhoto) { if let attempt = store.active { CompanionPhotoView(store: store, attemptID: attempt.id) } }
        .sheet(isPresented: Binding(get: { store.videoURL != nil }, set: { if !$0 { store.videoURL = nil } })) { if let url = store.videoURL { SourceVideoView(url: url) } }
        .sheet(isPresented: $timerEntry) {
            CookingTextEntry(title: "Set a timer", hint: "Minutes", message: "This timer will stay with the current step.", actionTitle: "Start timer", keyboard: .decimalPad, text: $timerMinutes) {
                guard let minutes = Double(timerMinutes.replacingOccurrences(of: ",", with: ".")), minutes.isFinite, (1...604800).contains(minutes * 60) else { return "Choose a duration from one second to seven days." }
                store.act("start_timer", seconds: minutes * 60)
                Task { await store.enableNotifications() }
                return nil
            }
        }
        .sheet(isPresented: $changeEntry) {
            CookingTextEntry(title: "Remember a change", hint: "e.g. used chicken thighs", message: "Keep substitutions and adjustments with this attempt.", actionTitle: "Save change", text: $changeText) {
                let text = changeText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, text.count <= 1000 else { return "Describe the change in 1–1,000 characters." }
                store.act("record_change", text: text); changeText = ""
                return nil
            }
        }
    }
    private func cooking(_ attempt: CookAttempt) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.stopVoice(); dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Save and leave cooking")
                Spacer()
                Button { showSteps = true } label: { Text("Step \(attempt.focusIndex + 1) of \(attempt.recipe.steps.count)").font(.caption).foregroundStyle(.secondary) }
                Menu {
                    Button("Record a substitution or change") { changeEntry = true }
                    Button(attempt.guidancePaused ? "Resume guidance" : "Pause guidance") { store.act(attempt.guidancePaused ? "resume_guidance" : "pause_guidance") }
                    Button("Repeat this step") { store.act("reopen_step") }
                    Button("Skip this step") { store.act("skip_step") }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Cooking options")
            }.padding(.horizontal, 14)
            ProgressView(value: Double(attempt.finishedSteps), total: Double(attempt.recipe.steps.count)).tint(Theme.green).padding(.horizontal, 26).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    Text((attempt.currentStep.component == "Main" ? attempt.currentStep.stage : attempt.currentStep.component + " · " + attempt.currentStep.stage).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Theme.green)
                    Text(attempt.currentStep.title).font(Theme.serif(37)).fixedSize(horizontal: false, vertical: true)
                    Text(attempt.currentStep.instruction).font(.system(size: 18)).foregroundStyle(Theme.ink.opacity(0.8)).lineSpacing(6)
                    if let cue = attempt.currentStep.visualCue {
                        HStack(alignment: .top, spacing: 12) { Image(systemName: "eye").padding(.top, 2); VStack(alignment: .leading, spacing: 7) { Text("LOOK FOR").font(.system(size: 9, weight: .semibold)).tracking(1.6); Text(cue).font(Theme.serif(21)).italic() } }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(Theme.sage.opacity(0.6), in: RoundedRectangle(cornerRadius: 17))
                    }
                    if let temperature = attempt.currentStep.temperature { Label(temperature, systemImage: "thermometer.medium").font(.subheadline.weight(.medium)) }
                    if !attempt.currentStep.ingredients.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("For this step").font(.subheadline.weight(.semibold))
                            ForEach(Array(attempt.currentStep.ingredients.enumerated()), id: \.offset) { _, item in
                                if let ingredient = attempt.recipe.ingredients.first(where: { $0.id == item.ingredientID }) { HStack(spacing: 10) { Image(systemName: ingredientSymbol(ingredient.name)).foregroundStyle(Theme.green); Text(ingredient.name); Spacer(); Text(item.quantity).foregroundStyle(.secondary) }.font(.subheadline) }
                            }
                        }
                    }
                    if let seconds = attempt.currentStep.durationSeconds {
                        Button { store.act("start_timer", seconds: seconds); Task { await store.enableNotifications() } } label: { Label("Start \(Int(seconds / 60))m \(Int(seconds) % 60)s timer\(attempt.currentStep.timingEstimated ? " · estimated" : "")", systemImage: "timer").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16)) }
                    }
                    ForEach(attempt.timers.filter { !$0.acknowledged }) { timer in timerCard(timer) }
                    HStack {
                        Button { timerEntry = true } label: { Label("Add timer", systemImage: "plus.circle") }
                        Spacer()
                        if attempt.currentStep.videoSeconds != nil { Button { store.showTechnique() } label: { Label("Show technique", systemImage: "play.rectangle") } }
                    }.font(.caption).frame(minHeight: 44)
                    if attempt.focusIndex + 1 < attempt.recipe.steps.count { VStack(alignment: .leading, spacing: 7) { Text("UP NEXT").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary); Text(attempt.recipe.steps[attempt.focusIndex + 1].title).font(.subheadline) }.padding(.vertical, 8) }
                    if let answer = store.lastAnswer { Text(answer).font(.subheadline).lineSpacing(5).padding(18).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16)) }
                    if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 26).padding(.bottom, 24)
            }
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    Button { if attempt.focusIndex > 0 { store.act("focus_step", target: attempt.recipe.steps[attempt.focusIndex - 1].id) } } label: { Image(systemName: "arrow.left").frame(width: 46, height: 46).background(.white.opacity(0.7), in: Circle()) }.disabled(attempt.focusIndex == 0).accessibilityLabel("Previous step")
                    Button(attempt.allStepsFinished ? "Finish cooking" : attempt.completed.contains(attempt.currentStep.id) || attempt.skipped.contains(attempt.currentStep.id) ? "Next unfinished step" : "Done, what’s next?") {
                        if attempt.allStepsFinished { store.act("finish") }
                        else if attempt.completed.contains(attempt.currentStep.id) || attempt.skipped.contains(attempt.currentStep.id) {
                            if let next = attempt.recipe.steps.first(where: { !attempt.completed.contains($0.id) && !attempt.skipped.contains($0.id) }) { store.act("focus_step", target: next.id) }
                        } else { store.act("complete_step") }
                    }.buttonStyle(FilledButton()).accessibilityIdentifier("complete-step")
                }
                HStack {
                    Button { showQuestions = true } label: { Image(systemName: "questionmark.bubble").font(.title3).frame(width: 48, height: 48) }.accessibilityLabel("Ask a question or show an ingredient")
                    Spacer()
                    Button { store.toggleVoice() } label: {
                        HStack(spacing: 10) { Image(systemName: store.voiceEnabled ? "waveform" : "mic.fill").font(.title3).frame(width: 45, height: 45).foregroundStyle(.white).background(Theme.green, in: Circle()); VStack(alignment: .leading, spacing: 3) { Text(store.voiceStatus).font(.caption.weight(.medium)); Text(store.voiceEnabled ? "Tap to stop" : "Your hands can stay busy").font(.system(size: 10)).foregroundStyle(.secondary) } }
                    }.accessibilityLabel(store.voiceEnabled ? "Stop listening" : "Start listening")
                    Spacer()
                    Button { showSteps = true } label: { Image(systemName: "list.bullet").font(.title3).frame(width: 48, height: 48) }.accessibilityLabel("All recipe steps")
                }
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8).background(Theme.cream)
        }
    }
    private func timerCard(_ timer: AttemptTimer) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date.timeIntervalSince1970 * 1000
            let seconds = Int(ceil(timer.remaining(at: now)))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: timer.expired(at: now) ? "bell.badge" : "timer").foregroundStyle(Theme.green)
                    VStack(alignment: .leading, spacing: 4) { Text(timer.label).font(.caption); Text(timer.expired(at: now) ? "Time to check" : String(format: "%d:%02d", seconds / 60, seconds % 60)).font(Theme.serif(28)).monospacedDigit() }
                    Spacer()
                    Button { store.act(timer.pausedSeconds == nil ? "pause_timer" : "resume_timer", target: timer.id) } label: { Image(systemName: timer.pausedSeconds == nil ? "pause.fill" : "play.fill").frame(width: 44, height: 44).background(Theme.sage, in: Circle()) }.accessibilityLabel(timer.pausedSeconds == nil ? "Pause \(timer.label)" : "Resume \(timer.label)")
                    Menu { Button("Add 3 minutes") { store.act("extend_timer", target: timer.id, seconds: 180) }; Button("Dismiss timer") { store.act("cancel_timer", target: timer.id) } } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }.accessibilityLabel("Timer options")
                }
                if timer.expired(at: now) { Text(timer.cue).font(.subheadline); Button("Checked") { store.act("acknowledge_timer", target: timer.id) }.font(.caption.weight(.semibold)) }
                else if timer.pausedSeconds != nil { Text("Paused").font(.caption).foregroundStyle(.secondary) }
            }.padding(17).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.green.opacity(timer.expired(at: now) ? 0.5 : 0.12)))
        }
    }
    private var stepsSheet: some View {
        NavigationStack { ScrollView { if let attempt = store.active { VStack(alignment: .leading, spacing: 20) { Text(attempt.recipe.title).font(Theme.serif(29)); ForEach(attempt.recipe.steps) { step in Button { store.act("focus_step", target: step.id); showSteps = false } label: { HStack(alignment: .top, spacing: 13) { Image(systemName: attempt.completed.contains(step.id) ? "checkmark.circle.fill" : attempt.skipped.contains(step.id) ? "forward.circle" : "circle"); VStack(alignment: .leading, spacing: 6) { Text(step.title).font(.headline); Text(step.stage).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(.vertical, 9) }.buttonStyle(.plain) } }.padding(25) } }.background(Theme.cream).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showSteps = false } } } }
    }
}

struct RecipeQuestionView: View {
    @Bindable var store: CompanionStore
    let recipe: CompanionRecipe
    @State private var question = ""
    @State private var image: UIImage?
    @State private var selection: PhotosPickerItem?
    @State private var camera = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    Text("A little help\nalong the way.").font(Theme.serif(36))
                    Text(recipe.title).font(.subheadline).foregroundStyle(Theme.green)
                    Text("Ask about an ingredient, a substitution, or what to look for. Your chef knows the recipe you’re making.").font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                    if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 17)); Button("Remove photo") { self.image = nil }.font(.caption) }
                    TextField("Ask anything…", text: $question, axis: .vertical).accessibilityIdentifier("recipe-question").lineLimit(2...5).padding(17).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Button { Task { if await AVCaptureDevice.requestAccess(for: .video), UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.error = "Camera unavailable. Choose a photo, or enable access in Settings." } } } label: { Label("Use camera", systemImage: "camera") }
                        Spacer(); PhotosPicker(selection: $selection, matching: .images) { Label("Choose photo", systemImage: "photo") }
                    }.font(.caption).frame(minHeight: 44)
                    Button { Task { await store.ask(question, recipe: recipe, image: image.flatMap(DishPhotoView.compressed)) } } label: { HStack { if store.asking { ProgressView().tint(.white) }; Text(store.asking ? "Your chef is thinking…" : "Ask your chef") } }.buttonStyle(FilledButton()).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.asking)
                    if let answer = store.lastAnswer { Text(answer).font(.body).lineSpacing(6).padding(20).background(Theme.sage.opacity(0.6), in: RoundedRectangle(cornerRadius: 19)) }
                    ForEach(["Can I substitute an ingredient?", "How should this look?", "What did I change last time?"], id: \.self) { prompt in Button { question = prompt } label: { Text(prompt).font(.caption).padding(.horizontal, 14).padding(.vertical, 11).overlay(Capsule().stroke(Theme.green.opacity(0.18))) } }
                    Text("Ingredient photos are used for this question. They aren’t added to your album.").font(.caption).foregroundStyle(.secondary)
                }.padding(25)
            }.background(Theme.cream).foregroundStyle(Theme.ink).keyboardDone().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.onAppear { store.lastAnswer = nil; store.stopVoice() }
        .fullScreenCover(isPresented: $camera) { CompanionCamera { image = $0; camera = false } }
        .onChange(of: selection) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { image = UIImage(data: data) } } }
    }
}

private struct CompanionCompletion: View {
    @Bindable var store: CompanionStore
    let attempt: CookAttempt
    @State private var detail = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                RecipePhoto(recipe: attempt.recipe).frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 26))
                Text("You did it!").font(Theme.serif(43))
                Text(attempt.recipe.title).font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    completionAction("Save photo", "camera") { store.showPhoto = true }
                    completionAction("Add a note", "square.and.pencil") { detail = true }
                    completionAction("Rate recipe", "star") { detail = true }
                }.padding(.vertical, 7)
                Text("Added to your cooking history").font(.subheadline.weight(.medium))
                Label("Your steps, timers and changes are saved. A photo is a lovely extra.", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Theme.green).lineSpacing(4)
                Button("Back to my cookbook") { store.showCooking = false }.buttonStyle(FilledButton()).padding(.top, 15)
            }.padding(25)
        }.sheet(isPresented: $detail) { AttemptDetailView(store: store, attemptID: attempt.id) }
    }
    private func completionAction(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 9) { Image(systemName: symbol).font(.title3).frame(width: 53, height: 53).background(Theme.sage, in: Circle()); Text(title).font(.caption) }.frame(maxWidth: .infinity) }.buttonStyle(.plain) }
}

private struct AttemptTile: View {
    let store: CompanionStore
    let attempt: CookAttempt
    @State private var image: UIImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group { if let image { Image(uiImage: image).resizable().scaledToFill() } else { ZStack { Theme.sage; Image(systemName: "camera").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Theme.green) } } }.frame(height: 155).clipped().clipShape(RoundedRectangle(cornerRadius: 17))
            Text(attempt.recipe.title).font(Theme.serif(20)).lineLimit(2).multilineTextAlignment(.leading)
            Text(Date(timeIntervalSince1970: (attempt.finishedAt ?? 0) / 1000), style: .date).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).task(id: attempt.photoFile ?? attempt.photoPath) { image = await store.loadPhoto(attempt) }
    }
}

struct AttemptDetailView: View {
    @Bindable var store: CompanionStore
    let attemptID: String
    @State private var note = ""
    @State private var rating = 0
    @State private var photo = false
    @State private var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    private var attempt: CookAttempt? { store.archive.attempts.first { $0.id == attemptID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let attempt {
                    VStack(alignment: .leading, spacing: 24) {
                        if let image { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20)) }
                        Text(attempt.recipe.title).font(Theme.serif(34))
                        Text(Date(timeIntervalSince1970: (attempt.finishedAt ?? attempt.startedAt) / 1000), style: .date).font(.subheadline).foregroundStyle(.secondary)
                        if let end = attempt.finishedAt { Label("\(max(1, Int((end - attempt.startedAt) / 60000))) minutes in your kitchen", systemImage: "clock").font(.caption) }
                        HStack(spacing: 15) { ForEach(1...5, id: \.self) { value in Button { rating = value } label: { Image(systemName: value <= rating ? "star.fill" : "star").font(.title2).frame(width: 40, height: 44) }.accessibilityLabel("Rate \(value) stars") } }
                        TextField("A note for next time…", text: $note, axis: .vertical).accessibilityIdentifier("cooking-note").lineLimit(3...8).padding(17).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                        Button { photo = true } label: { Label(image == nil ? "Add a dish photo" : "Replace dish photo", systemImage: "camera") }.frame(minHeight: 44)
                        if !attempt.changes.isEmpty { Text("Your changes").font(Theme.serif(25)); ForEach(attempt.changes, id: \.self) { Text($0).font(.subheadline) } }
                        DisclosureGroup("Cooking timeline") { ForEach(attempt.events) { event in HStack(alignment: .top) { Text(Date(timeIntervalSince1970: event.at / 1000), style: .time).font(.caption).foregroundStyle(.secondary); Text(event.kind.replacingOccurrences(of: "_", with: " ") + ": " + event.detail).font(.caption) }.padding(.vertical, 6) } }
                        if !attempt.messages.isEmpty { DisclosureGroup("Questions from this cook") { ForEach(attempt.messages) { message in VStack(alignment: .leading, spacing: 6) { Text(message.role == "user" ? "You" : "Your chef").font(.caption.weight(.semibold)); Text(message.text).font(.subheadline) }.padding(.vertical, 7) } } }
                        Button("Save memory") { store.updateAttempt(attemptID) { $0.notes = note; $0.rating = rating }; dismiss() }.buttonStyle(FilledButton())
                    }.padding(25)
                }
            }.background(Theme.cream).keyboardDone().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.onAppear { note = attempt?.notes ?? ""; rating = attempt?.rating ?? 0 }
        .task(id: attempt?.photoFile ?? attempt?.photoPath) { if let attempt { image = await store.loadPhoto(attempt) } }
        .sheet(isPresented: $photo) { CompanionPhotoView(store: store, attemptID: attemptID) }
    }
}

struct CompanionPhotoView: View {
    let store: CompanionStore
    let attemptID: String
    @State private var image: UIImage?
    @State private var selection: PhotosPickerItem?
    @State private var camera = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { ScrollView { VStack(spacing: 24) {
            Text("Made by you.").font(Theme.serif(37))
            Text("A little memory of something delicious.").font(.subheadline).foregroundStyle(.secondary)
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 330).clipShape(RoundedRectangle(cornerRadius: 22)) }
            else { Image(systemName: "camera").font(.system(size: 65, weight: .ultraLight)).foregroundStyle(Theme.green).frame(height: 180) }
            Button("Take a photo") { Task { if await AVCaptureDevice.requestAccess(for: .video), UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.error = "Camera unavailable. Choose a photo or enable camera access in Settings." } } }.buttonStyle(FilledButton())
            PhotosPicker(selection: $selection, matching: .images) { Label("Choose from Photos", systemImage: "photo") }.frame(minHeight: 44)
            if let image { Button("Save dish photo") { store.attachPhoto(image, attemptID: attemptID); dismiss() }.buttonStyle(FilledButton()) }
            Button("Skip for now") { dismiss() }.frame(minHeight: 44)
        }.padding(25) }.background(Theme.cream).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } } }
        .fullScreenCover(isPresented: $camera) { CompanionCamera { image = $0; camera = false } }
        .onChange(of: selection) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { image = UIImage(data: data) } } }
    }
}

struct CompanionCamera: UIViewControllerRepresentable {
    var finish: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finish: (UIImage?) -> Void
        init(finish: @escaping (UIImage?) -> Void) { self.finish = finish }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { finish(info[.originalImage] as? UIImage) }
    }
}
private struct SourceVideoView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
private func ingredientSymbol(_ name: String) -> String {
    let lower = name.lowercased()
    if lower.contains("oil") || lower.contains("water") { return "drop" }
    if lower.contains("milk") || lower.contains("cream") { return "mug" }
    if lower.contains("chicken") || lower.contains("meat") { return "fork.knife" }
    if lower.contains("fish") || lower.contains("salmon") { return "fish" }
    if lower.contains("flour") || lower.contains("pasta") || lower.contains("rice") { return "takeoutbag.and.cup.and.straw" }
    return "leaf"
}
