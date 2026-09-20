import SwiftUI

struct OnboardingView: View {
    let store: ChefStore
    var editing = false
    @State private var showAccount = false
    @State private var showIngredients = false
    @State private var step = 0
    @State private var preferences = ChefPreferences()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let titles = ["A sous chef\nthat listens.", "A kitchen\nthat fits you.", "A little care.\nBefore we cook.", "Your taste.\nYour pace.", "Your ingredients.\nYour choice.", "Already in\nyour kitchen.", "Make yourself\nat home."]
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 5) {
                            ForEach(titles.indices, id: \.self) { index in Capsule().fill(index <= step ? Theme.green : Theme.green.opacity(0.12)).frame(height: 4) }
                        }
                        Text("\(editing ? "YOUR PREFERENCES" : "A BRIGHTER TABLE")  ·  \(step + 1) / \(titles.count)")
                            .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Theme.green)
                        Text(titles[step]).font(.system(.largeTitle, design: .serif)).accessibilityAddTraits(.isHeader)
                        if step == 0 { welcome }
                        if step == 1 { dietary }
                        if step == 2 { allergies }
                        if step == 3 { taste }
                        if step == 4 { dislikes }
                        if step == 5 { equipment }
                        if step == 6 { guidance }
                    }.padding(.horizontal, 24).padding(.vertical, 16)
                }.scrollBounceBehavior(.basedOnSize).id(step)
                Button {
                    if step < titles.count - 1 { withAnimation { step += 1 } }
                    else { preferences.onboardingComplete = true; store.savePreferences(preferences); if editing { dismiss() } }
                } label: { HStack { Text(step == titles.count - 1 ? "Let's cook together" : step == 0 ? "Get started" : "Continue"); Image(systemName: "arrow.right") } }
                    .buttonStyle(FilledButton()).padding(.horizontal, 24).padding(.vertical, 12)
            }
            .background(Theme.cream).foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Oui Chef").font(Theme.serif(24)) }
                ToolbarItem(placement: .topBarLeading) { if step > 0 { Button { step -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous preferences") } }
                ToolbarItem(placement: .topBarTrailing) { if editing { Button("Close") { dismiss() } } }
            }
        }.onAppear { preferences = store.preferences }
            .onChange(of: store.preferences) { _, value in preferences = value }
            .sheet(isPresented: $showAccount) { AccountView() }
            .sheet(isPresented: $showIngredients) {
                if store.catalog != nil {
                    IngredientPickerView(store: store, selection: Binding(get: { preferences.dislikedFoodIDs ?? [] }, set: { preferences.dislikedFoodIDs = $0 }))
                }
            }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A little guidance, a little confidence, and something delicious at the end.").font(.body).foregroundStyle(.secondary)
            VoiceOrb(size: 170).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 18) {
                Label("Three recipes to make your own", systemImage: "book")
                Label("Timers that keep your place", systemImage: "timer")
                Label("Gentle check-ins, step by step", systemImage: "waveform")
            }.font(.subheadline)
            if !editing {
                Button(AccountSession.shared.accountID == nil ? "Sign in or create an account" : "Manage your account") { showAccount = true }
                    .font(.subheadline).frame(minHeight: 44)
            }
        }
    }
    private var dietary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What works for you?").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(["Vegetarian", "Vegan", "Gluten-free", "Dairy-free"], id: \.self) { option in
                    selection(option, selected: preferences.dietary.contains(option)) { toggle(option, in: &preferences.dietary) }
                }
            }
            Toggle("Avoid alcohol", isOn: $preferences.avoidAlcohol)
        }
    }
    private var allergies: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Food allergies").font(.headline)
            Text("Allergies are handled separately from taste. Always check packaging and cross-contact information.").font(.caption).foregroundStyle(.secondary)
            Picker("Allergy information", selection: $preferences.allergyAnswer) {
                ForEach(["Not specified", "None", "I have allergies"], id: \.self) { Text($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("allergy-answer")
            if preferences.allergyAnswer == "I have allergies" {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(["wheat", "gluten", "milk", "egg", "peanut", "tree nuts", "soy", "sesame", "fish", "shellfish"], id: \.self) { allergen in
                        selection(allergen.capitalized, selected: preferences.allergies.contains(allergen)) { toggle(allergen, in: &preferences.allergies) }
                    }
                }
            }
        }.onChange(of: preferences.allergyAnswer) { _, answer in if answer != "I have allergies" { preferences.allergies = [] } }
    }
    private var taste: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your saved taste choices apply automatically within each recipe's supported range. You can adjust them before cooking.").font(.subheadline).foregroundStyle(.secondary)
            tasteSlider("Spice", low: "Mild", high: "Hot", value: $preferences.spice)
            tasteSlider("Salt", low: "Less", high: "More", value: $preferences.salt)
            tasteSlider("Sweetness", low: "Less", high: "More", value: $preferences.sweetness)
        }
    }
    private var dislikes: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Anything you'd rather leave out? Choose from our ingredient library.").font(.subheadline).foregroundStyle(.secondary)
            Label("Dislikes are taste preferences. Add allergies on the allergy page.", systemImage: "leaf")
                .font(.subheadline).kitchenCard()
            Button { showIngredients = true } label: {
                Label("Choose ingredients", systemImage: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.bordered).tint(Theme.green)
            let names = (preferences.dislikedFoodIDs ?? []).compactMap { store.catalog?.food($0)?.name }.sorted()
            Text(names.isEmpty ? "No ingredients avoided" : "\(names.count) selected: " + names.prefix(5).joined(separator: ", ") + (names.count > 5 ? "…" : ""))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private var guidance: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Talk me through it", isOn: $preferences.detailedGuidance)
            Text("Helpful cues while you cook, and a warm check-in when you return. Turn this off for essential guidance only.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Keep screen awake while cooking", isOn: $preferences.keepScreenAwake)
            Toggle("Share usage measurements", isOn: $preferences.analyticsEnabled)
            Text("Optional counts of cooking actions, stored locally in this preview. No recordings, transcripts, or allergy details are included.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var equipment: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Select what you have. We'll skip reminders for your everyday tools and point out specialized equipment.")
                .font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ChefPreferences.equipmentChoices, id: \.self) { tool in
                    selection(tool, selected: preferences.equipment.contains(tool)) { toggle(tool, in: &preferences.equipment) }
                }
            }
            Text("Everyday utensils include a spoon, colander, mixing bowl, and serving glasses. You can update this in preferences.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func tasteSlider(_ title: String, low: String, high: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline.weight(.medium))
            Slider(value: value).accessibilityLabel(title)
            HStack { Text(low); Spacer(); Text(high) }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private func selection(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.green : Theme.green.opacity(0.3))
                Text(title).font(.subheadline)
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 48)
                .background(selected ? Theme.sage.opacity(0.6) : .white.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

struct ProfileView: View {
    let store: ChefStore
    @State private var showAccount = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your kitchen.").font(Theme.serif(40))
                Text("A little more confidence, every time you cook.").foregroundStyle(.secondary)
                HStack(spacing: 30) {
                    VStack(alignment: .leading) { Text("\(store.archive.dishes.count)").font(Theme.serif(40)); Text("recipes completed").font(.caption) }
                    VStack(alignment: .leading) { Text("\(store.archive.savedRecipes.count)").font(Theme.serif(40)); Text("recipes saved").font(.caption) }
                }.kitchenCard()
                Button { showAccount = true } label: {
                    HStack {
                        Label(AccountSession.shared.accountID == nil ? "Sign in or create an account" : AccountSession.shared.name, systemImage: "person.crop.circle")
                        Spacer(); Image(systemName: "chevron.right")
                    }.font(.subheadline).kitchenCard()
                }.buttonStyle(.plain).accessibilityIdentifier("account-button")
                VoiceSettingsView(store: store)
                Text("Completed recipes").font(Theme.serif(27))
                if store.archive.dishes.isEmpty { Text("Your first delicious memory is just a recipe away.").foregroundStyle(.secondary) }
                ForEach(store.archive.dishes) { dish in CompletedDishCard(store: store, dish: dish) }
                if store.hasMoreDishes { Button("Load more completed recipes") { Task { await store.loadDishes(more: true) } } }
                if let notice = store.dishNotice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                    Button("Retry sync") { store.syncDishes(); Task { await store.loadDishes() } }
                }
                ForEach(store.archive.history.filter { !$0.finished }) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.recipe.title).font(Theme.serif(23))
                        Text("Unfinished · \(session.completed.count) tasks completed").font(.caption)
                        Button("Resume cooking") { store.resumeAttempt(session.id) }
                    }.kitchenCard()
                }
                DisclosureGroup("Usage measurements") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.preferences.analyticsEnabled ? "Enabled · stored on this iPhone" : "Not enabled").font(.caption)
                        ForEach(Array(Set(store.archive.usage.map(\.name))).sorted(), id: \.self) { name in
                            HStack { Text(name.replacingOccurrences(of: "_", with: " ")); Spacer(); Text("\(store.archive.usage.filter { $0.name == name }.count)") }.font(.caption)
                        }
                    }.padding(.top, 12)
                }.kitchenCard()
            }.padding(24)
        }.refreshable { await store.loadDishes() }
        .task { await store.loadDishes() }
        .sheet(isPresented: $showAccount) { AccountView() }
    }
}

struct VoiceSettingsView: View {
    let store: ChefStore
    @AppStorage("useCloudVoice") private var useCloudVoice = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Use xAI voice", isOn: $useCloudVoice)
                .onChange(of: useCloudVoice) { _, _ in store.voice.stop() }
            Text("Audio and your cooking context are sent to xAI through Oui Chef while voice is on. Timers keep running when voice is off.").font(.caption).foregroundStyle(.secondary)
            if CloudVoiceAccount.endpoint == nil { Text("Cloud voice setup is pending.").font(.caption).foregroundStyle(Theme.orange) }
            if let id = store.voice.testerID {
                DisclosureGroup("Development tester ID") { Text(id).font(.caption.monospaced()).textSelection(.enabled) }
            }
        }.kitchenCard()
    }
}
