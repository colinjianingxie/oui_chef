import SwiftUI
import AuthenticationServices
import AVFoundation

struct CompanionWelcome: View {
    @Bindable var account = AccountSession.shared
    @State private var email = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Image("WelcomeFood").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: max(410, geometry.size.height * 0.66)).clipped()
                        .overlay(LinearGradient(stops: [.init(color: Theme.cream, location: 0), .init(color: Theme.cream.opacity(0.90), location: 0.27), .init(color: Theme.cream.opacity(0.25), location: 0.56), .init(color: .clear, location: 0.76)], startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 17) {
                                HStack { SectionEyebrow(title: "Oui Chef"); Spacer(); ChefMascot(size: 45) }
                                Text("A smarter way\nto cook for\nreal life.").font(Theme.serif(43)).lineSpacing(-2).foregroundStyle(Theme.plum)
                                Text("Bring a recipe you love.\nYour chef will guide you, step by step.").font(.subheadline).foregroundStyle(Theme.ink).lineSpacing(4)
                            }.padding(.horizontal, 28).padding(.top, 12)
                        }
                    VStack(spacing: 12) {
                        SignInWithAppleButton(.continue) { account.prepareApple($0) } onCompletion: { result in Task { await account.completeApple(result, intent: .signIn) } }
                            .signInWithAppleButtonStyle(.black).frame(height: 52).clipShape(Capsule()).disabled(account.busy)
                        Button { Task { await account.google(intent: .signIn) } } label: {
                            Text("Continue with Google").font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52).background(Capsule().stroke(Theme.plum.opacity(0.25))).contentShape(Capsule())
                        }.buttonStyle(.plain).disabled(account.busy)
                        Button { email = true } label: { Label("Continue with email", systemImage: "envelope").font(.body).frame(maxWidth: .infinity, minHeight: 50).background(Capsule().stroke(Theme.plum.opacity(0.25))).contentShape(Capsule()) }.buttonStyle(.plain)
                        if account.busy { ProgressView() }
                        if let error = account.error { Text(error).font(.caption).foregroundStyle(Theme.warning) }
                        LegalLinks()
                    }.foregroundStyle(Theme.plum).padding(24).background(Theme.cream, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)).padding(.top, -22)
                }
            }.background(Theme.cream).ignoresSafeArea(edges: .bottom)
        }.sheet(isPresented: $email) { AccountView(emailOnly: true) }
    }
}

enum PreferencePage: String, Identifiable { case diet, kitchen, voice; var id: String { rawValue } }

struct CompanionPreferences: View {
    let store: CompanionStore
    var onboarding = false
    var section: PreferencePage = .diet
    @State private var draft = CookProfile()
    @State private var page = 0
    @State private var loaded = false
    @State private var picker: PreferenceSection?
    @Environment(\.dismiss) private var dismiss
    private let diets = [("Everything", "A little bit of everything", "fork.knife"), ("Vegetarian", "Plants, dairy & eggs", "carrot"), ("Vegan", "Entirely plant based", "leaf"), ("Pescatarian", "Plants & seafood", "fish")]
    private var title: String {
        if onboarding { return ["What’s your\ncooking style?", "Tell us your tastes.", "A little about\nyour kitchen."][page] }
        return section == .diet ? "Your tastes,\nyour way." : section == .kitchen ? "At home in\nyour kitchen." : "A chef who\nlistens to you."
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if onboarding {
                        HStack { Text("\(page + 1) of 3"); Spacer(); if !draft.needsPreferenceReview { Button("Set up later") { finish() } } }.font(.caption).foregroundStyle(Theme.muted)
                        HStack(spacing: 5) { ForEach(0..<3) { i in Capsule().fill(i <= page ? Theme.plum : Theme.line).frame(height: 4) } }.accessibilityLabel("Onboarding step \(page + 1) of 3")
                    }
                    Text(title).font(Theme.serif(36)).foregroundStyle(Theme.plum).accessibilityAddTraits(.isHeader)
                    Text(onboarding ? "A few preferences help your chef guide you. You can change these anytime." : "Changes apply when you prepare your next recipe. Your cooking history stays as it was.").font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(3)
                    if draft.needsPreferenceReview {
                        VStack(alignment: .leading, spacing: 8) { Text("Review your earlier preferences").font(.headline); ForEach(draft.previousPreferencesPendingReview.keys.sorted(), id: \.self) { key in Text("\(key.capitalized): \(draft.previousPreferencesPendingReview[key] ?? "")").font(.subheadline) } }.padding(16).background(Theme.blush, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if onboarding ? page == 0 : section == .diet { dietary }
                    if onboarding ? page == 1 : section == .diet { tastes }
                    if onboarding ? page == 2 : section == .kitchen { kitchen }
                    if onboarding ? page == 2 : section == .voice { voice }
                    if onboarding && page == 1 { ChefCallout(text: "There are no wrong answers — just better recipes for you.") }
                }.padding(24)
            }.background(Theme.cream).foregroundStyle(Theme.ink).keyboardDone()
                .safeAreaInset(edge: .bottom) {
                    Button(onboarding && page < 2 ? "Next" : onboarding ? "Open my kitchen" : "Save preferences") {
                        if onboarding && page < 2 { page += 1; draft.onboardingStep = page; store.setProfile(draft) }
                        else { finish() }
                    }.buttonStyle(FilledButton()).padding(.horizontal, 24).padding(.vertical, 12).background(Theme.cream)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if onboarding { Button { page = max(0, page - 1); draft.onboardingStep = page; store.setProfile(draft) } label: { Image(systemName: "arrow.left") }.disabled(page == 0).accessibilityLabel("Previous setup step") }
                        else { Button("Close") { dismiss() } }
                    }
                }
        }
        .onAppear { guard !loaded else { return }; draft = store.profile; page = min(2, max(0, draft.onboardingStep)); loaded = true }
        .onChange(of: draft) { _, value in if onboarding && loaded { store.setProfile(value) } }
        .sheet(item: $picker) { PreferenceChecklist(section: $0, profile: $draft) }
    }
    private var dietary: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 2) {
                ForEach(diets, id: \.0) { item in
                    Button { draft.diet = item.0 } label: {
                        HStack(spacing: 15) {
                            Image(systemName: item.2).font(.system(size: 24, weight: .light)).foregroundStyle(Theme.plum).frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) { Text(item.0).font(.body); Text(item.1).font(.caption).foregroundStyle(Theme.muted) }
                            Spacer(); Image(systemName: draft.diet == item.0 ? "checkmark.circle.fill" : "circle").foregroundStyle(draft.diet == item.0 ? Theme.plum : Theme.line)
                        }.padding(14).background(draft.diet == item.0 ? Theme.blush.opacity(0.65) : .clear, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityAddTraits(draft.diet == item.0 ? .isSelected : [])
                }
            }
            selectionRow(.allergies)
            Text("Allergies need special care. Substitutions are suggestions, never a guarantee that an ingredient is safe for you.").font(.caption).foregroundStyle(Theme.muted)
            TextField("Another allergy (optional)", text: $draft.customAllergies, axis: .vertical).lineLimit(1...3).font(.subheadline).padding(14).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 12)).onChange(of: draft.customAllergies) { _, value in draft.customAllergies = String(value.prefix(500)); if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.allergyStatus = .selected } }
            selectionRow(.restrictions)
            TextField("Other dietary restrictions (optional)", text: $draft.customRestrictions, axis: .vertical).lineLimit(1...3).font(.subheadline).padding(14).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 12)).onChange(of: draft.customRestrictions) { _, value in draft.customRestrictions = String(value.prefix(500)) }
        }
    }
    private var tastes: some View {
        VStack(alignment: .leading, spacing: 24) {
            choice("Spice level", value: $draft.spice, options: ["Mild", "Medium", "Hot"])
            choice("Salt preference", value: $draft.salt, options: ["Lower", "Balanced", "Higher"])
            selectionRow(.dislikes)
            choice("Cooking experience", value: $draft.experience, options: ["Beginner", "Home cook", "Confident"])
            Text("We’ll adjust the detail of your guidance, while keeping every essential cooking instruction.").font(.caption).foregroundStyle(Theme.muted)
        }
    }
    private var kitchen: some View {
        VStack(alignment: .leading, spacing: 24) {
            Stepper("Usually cooking for \(draft.servings)", value: $draft.servings, in: 1...20)
            Stepper("Household size: \(draft.householdSize)", value: $draft.householdSize, in: 1...20)
            choice("Measurement units", value: $draft.units, options: ["Metric", "US customary"])
            selectionRow(.equipment)
            Text("Equipment is optional to set up. We’ll show what each recipe needs before you cook.").font(.caption).foregroundStyle(Theme.muted)
        }.font(.subheadline)
    }
    private var voice: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recipe & chef language").font(.subheadline.weight(.medium))
                TextField("English", text: $draft.voiceLanguage).textInputAutocapitalization(.words).padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("voice-language").onChange(of: draft.voiceLanguage) { _, value in draft.voiceLanguage = String(value.prefix(80)) }
            }
            Toggle("Keep screen awake while cooking", isOn: $draft.keepAwake)
            Toggle("Gentle cooking reminders", isOn: $draft.gentleGuidance)
            Toggle("Speak chef answers", isOn: $draft.spokenAnswers)
            Text("You choose when the microphone is on. Listening ends when you leave cooking or put the app in the background.").font(.caption).foregroundStyle(Theme.muted)
            if !onboarding {
                Button("Manage notification permissions") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(.subheadline).frame(minHeight: 44)
            }
        }.font(.subheadline)
    }
    private func selectionRow(_ section: PreferenceSection) -> some View {
        let names = section.names(draft.selectedIDs(section))
        let empty = section == .allergies ? (draft.allergyStatus == .noneKnown ? "No known allergies" : "Not specified") : section == .equipment ? "Select what you have · optional" : "Choose options"
        return Button { picker = section } label: {
            HStack(spacing: 14) { VStack(alignment: .leading, spacing: 5) { Text(section.title).font(.subheadline.weight(.medium)); Text(names.isEmpty ? empty : names.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.leading) }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.plum) }.padding(16).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier("preferences-" + section.rawValue)
    }
    private func choice(_ title: String, value: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.subheadline.weight(.medium)); Picker(title, selection: value) { ForEach(options, id: \.self) { Text($0) } }.pickerStyle(.segmented) }
    }
    private func finish() {
        draft.voiceLanguage = draft.voiceLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.voiceLanguage.isEmpty { draft.voiceLanguage = "English" }
        draft.onboardingComplete = true; draft.onboardingStep = 2; draft.previousPreferencesPendingReview = [:]
        if store.setProfile(draft) { dismiss() }
    }
}

struct LegalLinks: View {
    private func url(_ key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    var body: some View {
        HStack(spacing: 12) {
            if let terms = url("OuiChefTermsURL") { Link("Terms of Service", destination: terms) }
            if let privacy = url("OuiChefPrivacyURL") { Link("Privacy Policy", destination: privacy) }
        }.font(.caption).foregroundStyle(Theme.muted).frame(minHeight: 30)
    }
}
