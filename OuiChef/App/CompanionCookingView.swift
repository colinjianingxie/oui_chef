import SwiftUI
import PhotosUI
import AVFoundation

struct CompanionCookingView: View {
    @Bindable var store: CompanionStore
    @State private var showSteps = false
    @State private var showTimers = false
    @State private var showConversation = false
    @State private var timerEntry = false
    @State private var timerMinutes = "3"
    @State private var renameTimer: AttemptTimer?
    @State private var pendingRename: AttemptTimer?
    @State private var timerName = ""
    @State private var changeEntry = false
    @State private var changeText = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let attempt = store.active {
                    if attempt.finishedAt != nil { CompanionCompletion(store: store, attempt: attempt) }
                    else if attempt.isPreparing { preparation(attempt) }
                    else { cooking(attempt) }
                } else { ContentUnavailableView("Choose a recipe", systemImage: "book.closed") }
            }.background(Theme.cream).foregroundStyle(Theme.ink).toolbar(.hidden, for: .navigationBar)
        }
        .onDisappear { store.stopVoice() }
        .sheet(isPresented: $showSteps) { stepsSheet }
        .sheet(isPresented: $showTimers, onDismiss: { renameTimer = pendingRename; pendingRename = nil }) { timersSheet }
        .sheet(isPresented: $showConversation) { conversation }
        .sheet(isPresented: $store.showPhoto) { if let attempt = store.active { CompanionPhotoView(store: store, attemptID: attempt.id) } }
        .sheet(isPresented: Binding(get: { store.videoURL != nil }, set: { if !$0 { store.videoURL = nil } })) { if let url = store.videoURL { SourceVideoView(url: url) } }
        .sheet(isPresented: $timerEntry) {
            CookingTextEntry(title: "Set a timer", hint: "Minutes", message: "Keep track of one thing while you cook another.", actionTitle: "Start timer", keyboard: .decimalPad, text: $timerMinutes) {
                guard let minutes = Double(timerMinutes.replacingOccurrences(of: ",", with: ".")), minutes.isFinite, (1...604800).contains(minutes * 60) else { return "Choose a duration from one second to seven days." }
                store.act("start_timer", seconds: minutes * 60, additional: true); Task { await store.enableNotifications() }; return nil
            }
        }
        .sheet(item: $renameTimer) { timer in CookingTextEntry(title: "Rename timer", hint: "Timer name", message: "The countdown will keep running.", actionTitle: "Save name", text: $timerName) {
            guard !timerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, timerName.count <= 100 else { return "Use 1–100 characters." }
            store.act("rename_timer", target: timer.id, text: timerName); return nil
        } }
        .sheet(isPresented: $changeEntry) { CookingTextEntry(title: "Remember a change", hint: "e.g. used chicken thighs", message: "Keep a substitution or adjustment with this cook.", actionTitle: "Save change", text: $changeText) {
            let text = changeText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 1000 else { return "Describe your change in 1–1,000 characters." }
            store.act("record_change", text: text); changeText = ""; return nil
        } }
    }
    private func close() { store.stopVoice(); dismiss() }
    private func preparation(_ attempt: CookAttempt) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Button(action: close) { Image(systemName: "xmark").font(.system(size: 22)).frame(width: 44, height: 44) }.accessibilityLabel("Save and leave cooking"); Spacer(); SectionEyebrow(title: "Before you begin") }
                Text("Let’s get ready.").font(Theme.serif(37)).foregroundStyle(Theme.plum)
                Text("Gather your ingredients. Your checklist will be here when you come back.").font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(4)
                Text("Check what you have. When you’re ready, you can continue with unchecked items or ask your chef about a substitute.").font(.caption).foregroundStyle(Theme.muted)
                HStack { Text(attempt.recipe.title).font(.subheadline.weight(.medium)); Spacer(); Text(attempt.recipe.servings.map { "\($0) servings" } ?? "").font(.caption).foregroundStyle(Theme.muted) }
                Button(Set(attempt.preparation?.ingredientIDs ?? []).count == attempt.recipe.ingredients.count ? "Deselect all ingredients" : "Select all ingredients") {
                    let all = Set(attempt.preparation?.ingredientIDs ?? []).count == attempt.recipe.ingredients.count
                    store.updateAttempt(attempt.id) { $0.preparation?.ingredientIDs = all ? [] : $0.recipe.ingredients.map(\.id) }
                }.font(.caption.weight(.medium)).frame(minHeight: 44).accessibilityIdentifier("select-all-ingredients")
                IngredientRows(recipe: attempt.recipe, ingredients: attempt.recipe.ingredients.filter { !$0.pantry }, checked: Set(attempt.preparation?.ingredientIDs ?? [])) { store.act("check_ingredient", target: $0) }
                if attempt.recipe.ingredients.contains(where: \.pantry) {
                    DisclosureGroup("Pantry basics") { IngredientRows(recipe: attempt.recipe, ingredients: attempt.recipe.ingredients.filter(\.pantry), checked: Set(attempt.preparation?.ingredientIDs ?? [])) { store.act("check_ingredient", target: $0) }.padding(.top, 12) }.font(.subheadline)
                }
                if !attempt.recipe.equipment.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Have these handy.").font(Theme.serif(25)).foregroundStyle(Theme.plum)
                        ForEach(attempt.recipe.equipment, id: \.self) { tool in
                            Button { store.act("check_equipment", target: tool) } label: { HStack { Text(tool); Spacer(); Image(systemName: attempt.preparation?.equipment.contains(tool) == true ? "checkmark.circle.fill" : "circle") }.font(.subheadline).frame(minHeight: 44) }.buttonStyle(.plain)
                        }
                    }
                }
                if !attempt.recipe.preparation.isEmpty {
                    VStack(alignment: .leading, spacing: 12) { SectionEyebrow(title: "Before you begin"); ForEach(attempt.recipe.preparation, id: \.self) { Text($0).font(.body).lineSpacing(4) } }
                }
                if !attempt.recipe.reviewNotes.isEmpty {
                    RecipeReviewNotes(notes: attempt.recipe.reviewNotes)
                    Toggle("I’ve reviewed these notes", isOn: Binding(get: { attempt.preparation?.reviewedVersion == attempt.recipe.version }, set: { store.act("review_recipe", text: $0 ? "accepted" : "unreviewed") })).font(.subheadline).accessibilityIdentifier("review-preparation")
                }
                DisclosureGroup("Missing something? Ask about a substitute") { InlineChefQuestion(store: store, recipe: attempt.recipe).padding(.top, 14) }.font(.subheadline)
                if let answer = store.lastAnswer { ChefAnswer(text: answer) { showConversation = true } }
                pendingChange
                voiceError
            }.padding(.horizontal, 24).padding(.bottom, 28)
        }.safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                Button { store.toggleVoice() } label: { MicrophoneRings(active: store.voiceEnabled, symbol: store.voiceEnabled ? "mic.slash.fill" : "mic.fill", size: 66) }.accessibilityLabel(store.voiceEnabled ? "Stop listening" : "Start listening")
                VStack(alignment: .leading, spacing: 5) { Text(store.voiceStatus).font(.caption).foregroundStyle(Theme.muted); Button("I’m ready to cook") { store.act("begin_cooking"); Task { await store.enableNotifications() } }.buttonStyle(FilledButton()).disabled(!attempt.recipe.reviewNotes.isEmpty && attempt.preparation?.reviewedVersion != attempt.recipe.version).accessibilityIdentifier("begin-cooking") }
            }.padding(.horizontal, 24).padding(.vertical, 10).background(Theme.cream)
        }
    }
    private func cooking(_ attempt: CookAttempt) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 22)).frame(width: 44, height: 44) }.accessibilityLabel("Save and leave cooking")
                Spacer()
                Button { showSteps = true } label: { Text("Step \(attempt.focusIndex + 1) of \(attempt.recipe.steps.count)").font(.caption).foregroundStyle(Theme.muted) }.accessibilityLabel("All recipe steps")
                Menu {
                    Button("Record a substitution or change") { changeEntry = true }
                    Button(attempt.guidancePaused ? "Resume guidance" : "Pause guidance") { store.act(attempt.guidancePaused ? "resume_guidance" : "pause_guidance") }
                    Button("Repeat this step") { store.act("reopen_step") }
                    Button("Skip this step") { store.act("skip_step") }
                } label: { Image(systemName: "ellipsis").font(.system(size: 22)).frame(width: 44, height: 44) }.accessibilityLabel("Cooking options")
            }.padding(.horizontal, 14)
            ProgressView(value: Double(attempt.finishedSteps), total: Double(attempt.recipe.steps.count)).tint(Theme.plum).padding(.horizontal, 24).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SectionEyebrow(title: attempt.currentStep.stage)
                    Text(attempt.currentStep.title).font(Theme.serif(36)).foregroundStyle(Theme.plum).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("current-step-title")
                    if let baseline = attempt.recipe.portionBaseline { Text("Source directions · \(baseline.servings) servings. Use the adjusted quantities below.").font(.caption).foregroundStyle(Theme.warning) }
                    Text(attempt.currentStep.instruction).font(.body).lineSpacing(6).accessibilityIdentifier("current-step-instruction")
                    if !attempt.currentStep.ingredients.isEmpty { stepIngredients(attempt) }
                    if let cue = attempt.currentStep.visualCue {
                        HStack(alignment: .top, spacing: 13) { Image(systemName: "lightbulb").font(.title3).foregroundStyle(Theme.berry); VStack(alignment: .leading, spacing: 6) { Text("Look for").font(.caption.weight(.semibold)).foregroundStyle(Theme.berry); Text(cue).font(.subheadline).lineSpacing(3) } }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Theme.blush.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if let temperature = attempt.currentStep.temperature { Label(temperature, systemImage: "thermometer.medium").font(.subheadline.weight(.medium)) }
                    if let seconds = attempt.currentStep.durationSeconds, !attempt.timers.contains(where: { $0.stepID == attempt.currentStep.id && !$0.acknowledged && $0.additional != true }) {
                        Button { store.act("start_timer", target: attempt.currentStep.id, seconds: seconds); Task { await store.enableNotifications() } } label: { Label("Start \(duration(seconds)) timer", systemImage: "timer").font(.subheadline.weight(.medium)).frame(minHeight: 44) }.accessibilityIdentifier("start-step-timer")
                    }
                    if attempt.currentStep.videoSeconds != nil { Button { store.showTechnique() } label: { Label("Watch this moment in the source ↗", systemImage: "play.rectangle").font(.subheadline).frame(minHeight: 44) } }
                    pendingChange
                    DisclosureGroup("Ask a question or show an ingredient") { InlineChefQuestion(store: store, recipe: attempt.recipe).padding(.top, 16) }.font(.subheadline)
                    voiceError
                    if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(Theme.muted) }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            dock(attempt)
        }
    }
    private func stepIngredients(_ attempt: CookAttempt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "For this step")
            ForEach(Array(attempt.currentStep.ingredients.enumerated()), id: \.offset) { _, item in
                if let ingredient = attempt.recipe.ingredients.first(where: { $0.id == item.ingredientID }) {
                    HStack(alignment: .top) { Text(ingredient.name); Spacer(); Text(item.quantity).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing) }.font(.subheadline)
                }
            }
        }
    }
    @ViewBuilder private var pendingChange: some View {
if let change = store.pendingVoiceChange {
                        VStack(alignment: .leading, spacing: 12) { Text("Save this change?").font(.headline); Text(change.text ?? "").font(.subheadline); HStack { Button("Save change") { store.acceptVoiceChange() }.buttonStyle(FilledButton()); Button("Dismiss") { store.pendingVoiceChange = nil }.frame(minHeight: 44) } }.padding(16).background(Theme.blush, in: RoundedRectangle(cornerRadius: 16))
                    }
    }
    @ViewBuilder private var voiceError: some View {
        if case .error(let message) = store.voiceState {
            VStack(alignment: .leading, spacing: 8) { Label(message, systemImage: "mic.slash").font(.subheadline); HStack { Button("Try voice again") { store.toggleVoice() }; Spacer(); Button("Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }.font(.caption).frame(minHeight: 44) }.foregroundStyle(Theme.warning)
        }
    }
    private func dock(_ attempt: CookAttempt) -> some View {
        VStack(spacing: 5) {
            if let answer = store.lastAnswer {
                Button { showConversation = true } label: {
                    HStack(alignment: .center, spacing: 10) { ChefMascot(size: 30); Text(answer).font(.caption).lineLimit(2).multilineTextAlignment(.leading); Spacer(minLength: 0); Image(systemName: "chevron.up").font(.caption) }.padding(12).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).background(Theme.blush.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel("Recent chef advice: " + answer).accessibilityIdentifier("compact-chef-answer")
            }
            if !attempt.timers.filter({ !$0.acknowledged }).isEmpty {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let timers = attempt.timers.filter { !$0.acknowledged }.sorted { $0.deadline < $1.deadline }
                    if let timer = timers.first {
                        HStack {
                            Button { showTimers = true } label: { HStack(spacing: 8) { Image(systemName: "timer"); Text(timer.label).lineLimit(1); Text(timer.expired(at: context.date.timeIntervalSince1970 * 1000) ? "Time to check" : countdown(timer, at: context.date)).monospacedDigit().fontWeight(.semibold).accessibilityIdentifier("timer-remaining-\(timer.stepID)"); if timers.count > 1 { Text("+\(timers.count - 1)") } }.font(.caption).frame(minHeight: 44) }
                            Spacer(minLength: 4)
                            Button { store.act(timer.expired(at: context.date.timeIntervalSince1970 * 1000) ? "acknowledge_timer" : timer.pausedSeconds == nil ? "pause_timer" : "resume_timer", target: timer.id) } label: { Image(systemName: timer.expired(at: context.date.timeIntervalSince1970 * 1000) ? "checkmark" : timer.pausedSeconds == nil ? "pause.fill" : "play.fill").font(.system(size: 18)).frame(width: 44, height: 44) }.accessibilityLabel(timer.expired(at: context.date.timeIntervalSince1970 * 1000) ? "Checked timer" : timer.pausedSeconds == nil ? "Pause \(timer.label)" : "Resume \(timer.label)")
                        }.padding(.horizontal, 14).background(Theme.blush.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            HStack(spacing: 10) {
                Button { if attempt.focusIndex > 0 { store.act("focus_step", target: attempt.recipe.steps[attempt.focusIndex - 1].id) } } label: { Image(systemName: "arrow.left").font(.system(size: 22)).frame(width: 44, height: 48) }.disabled(attempt.focusIndex == 0).accessibilityLabel("Previous step")
                Button { timerEntry = true } label: { Image(systemName: "timer").font(.system(size: 22)).frame(width: 44, height: 48) }.accessibilityLabel("Add timer")
                Spacer(minLength: 0)
                Button { store.toggleVoice() } label: { MicrophoneRings(active: store.voiceEnabled, symbol: store.voiceEnabled ? "mic.slash.fill" : "mic.fill", size: 76) }.accessibilityLabel(store.voiceEnabled ? "Stop listening" : "Start listening")
                Spacer(minLength: 0)
                Button { complete(attempt) } label: { VStack(spacing: 5) { Image(systemName: attempt.allStepsFinished ? "checkmark" : "arrow.right").font(.system(size: 22)); Text(attempt.allStepsFinished ? "Finish" : "Next").font(.caption.weight(.medium)) }.padding(.horizontal, 12).padding(.vertical, 7).frame(minWidth: 64, minHeight: 54).foregroundStyle(.white).background(Theme.plum, in: RoundedRectangle(cornerRadius: 18)) }.accessibilityLabel(attempt.allStepsFinished ? "Finish cooking" : "Complete step and continue").accessibilityIdentifier("complete-step")
            }
            HStack(spacing: 8) {
                Text(store.voiceStatus).font(.caption.weight(.medium))
                if store.microphoneActive { Text("· Microphone on").font(.caption).foregroundStyle(Theme.muted) }
                if store.voiceState == .speaking { Button("Interrupt") { store.interruptVoice() }.font(.caption.weight(.semibold)).frame(minHeight: 32) }
                Spacer()
                if !attempt.messages.isEmpty { Button("Chef advice") { showConversation = true }.font(.caption).frame(minHeight: 32) }
            }.foregroundStyle(Theme.plum).padding(.horizontal, 5)
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8).background(Theme.cream).overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
    private func complete(_ attempt: CookAttempt) {
        if attempt.allStepsFinished { store.act("finish") }
        else if attempt.completed.contains(attempt.currentStep.id) || attempt.skipped.contains(attempt.currentStep.id) {
            if let next = attempt.recipe.steps.first(where: { !attempt.completed.contains($0.id) && !attempt.skipped.contains($0.id) }) { store.act("focus_step", target: next.id) }
        } else { store.act("complete_step") }
    }
    private var stepsSheet: some View {
        NavigationStack { List { if let attempt = store.active { ForEach(attempt.recipe.steps) { step in Button { store.act("focus_step", target: step.id); showSteps = false } label: { HStack(spacing: 14) { Image(systemName: attempt.completed.contains(step.id) ? "checkmark.circle.fill" : attempt.skipped.contains(step.id) ? "forward.circle" : "circle"); VStack(alignment: .leading, spacing: 6) { Text(step.title).font(.headline); Text(step.stage).font(.caption).foregroundStyle(Theme.muted) } }.padding(.vertical, 8) }.buttonStyle(.plain).listRowBackground(Theme.cream) } } }.listStyle(.plain).background(Theme.cream).scrollContentBackground(.hidden).navigationTitle("Your recipe steps").navigationBarTitleDisplayMode(.inline).toolbar { Button("Close") { showSteps = false } } }
    }
    private var timersSheet: some View {
        NavigationStack { ScrollView { VStack(spacing: 18) {
            if let attempt = store.active { TimelineView(.periodic(from: .now, by: 1)) { context in ForEach(attempt.timers.filter { !$0.acknowledged }) { timer in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(timer.label).font(.headline); Spacer(); Menu { Button("Rename") { timerName = timer.label; pendingRename = timer; showTimers = false }; Button("Add 3 minutes") { store.act("extend_timer", target: timer.id, seconds: 180) }; Button("Cancel timer", role: .destructive) { store.act("cancel_timer", target: timer.id) } } label: { Image(systemName: "ellipsis").font(.system(size: 22)).frame(width: 44, height: 44) } }
                    Text(timer.expired(at: context.date.timeIntervalSince1970 * 1000) ? "Time to check" : countdown(timer, at: context.date)).font(Theme.serif(36)).monospacedDigit().foregroundStyle(Theme.plum)
                    if timer.expired(at: context.date.timeIntervalSince1970 * 1000) { Text(timer.cue).font(.subheadline); Button("Checked") { store.act("acknowledge_timer", target: timer.id) }.frame(minHeight: 44) }
                    else { Button(timer.pausedSeconds == nil ? "Pause timer" : "Resume timer") { store.act(timer.pausedSeconds == nil ? "pause_timer" : "resume_timer", target: timer.id) }.frame(minHeight: 44) }
                }.padding(18).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
            } } }
        }.padding(24) }.background(Theme.cream).navigationTitle("Your timers").navigationBarTitleDisplayMode(.inline).toolbar { Button("Close") { showTimers = false } } }.presentationDetents([.medium, .large])
    }
    private var conversation: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 24) {
            if let attempt = store.active { HStack(spacing: 14) { ChefMascot(size: 54); VStack(alignment: .leading, spacing: 5) { Text(attempt.recipe.title).font(.headline); Text("Step \(attempt.focusIndex + 1) · \(attempt.currentStep.title)").font(.caption).foregroundStyle(Theme.muted) } }; ForEach(attempt.messages) { message in VStack(alignment: .leading, spacing: 7) { SectionEyebrow(title: message.role == "user" ? "You" : "Your chef"); Text(message.text).font(.body).lineSpacing(4) } }; InlineChefQuestion(store: store, recipe: attempt.recipe) }
        }.padding(24) }.background(Theme.cream).navigationTitle("Chef advice").navigationBarTitleDisplayMode(.inline).toolbar { Button("Back to cooking") { showConversation = false } } }.presentationDetents([.medium, .large])
    }
    private func duration(_ seconds: Double) -> String { let total = Int(seconds); return total < 60 ? "\(total)s" : total % 60 == 0 ? "\(total / 60)m" : "\(total / 60)m \(total % 60)s" }
    private func countdown(_ timer: AttemptTimer, at date: Date) -> String { let seconds = Int(ceil(timer.remaining(at: date.timeIntervalSince1970 * 1000))); return String(format: "%d:%02d", seconds / 60, seconds % 60) + (timer.pausedSeconds == nil ? "" : " · Paused") }
}

struct ChefAnswer: View {
    let text: String
    let expand: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { HStack(spacing: 10) { ChefMascot(size: 34); Text("Your chef").font(.caption.weight(.semibold)).foregroundStyle(Theme.plum); Spacer(); Button(action: expand) { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }.accessibilityLabel("Show chef advice") }; Text(text).font(.subheadline).lineSpacing(4).textSelection(.enabled) }.padding(16).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct InlineChefQuestion: View {
    @Bindable var store: CompanionStore
    var recipe: CompanionRecipe?
    @State private var question = ""
    @State private var image: UIImage?
    @State private var selection: PhotosPickerItem?
    @State private var camera = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 12)); Button("Remove photo") { self.image = nil }.font(.caption) }
            TextField("Ask your chef…", text: $question, axis: .vertical).lineLimit(1...4).padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("recipe-question")
            HStack {
                PhotosPicker(selection: $selection, matching: .images) { Image(systemName: "photo").frame(width: 44, height: 44) }.accessibilityLabel("Choose ingredient photo")
                Button { Task { if await AVCaptureDevice.requestAccess(for: .video), UIImagePickerController.isSourceTypeAvailable(.camera) { store.stopVoice(muted: true); camera = true } else { store.error = "Camera unavailable. Choose a photo or allow camera access in Settings." } } } label: { Image(systemName: "camera").frame(width: 44, height: 44) }.accessibilityLabel("Take ingredient photo")
                Spacer()
                Button { let text = question; dismissCookingKeyboard(); Task { if await store.ask(text, recipe: recipe, image: image.flatMap(DishPhoto.compressed)) { question = "" } } } label: { HStack { if store.asking { ProgressView() }; Text(store.asking ? "Thinking…" : "Ask your chef"); Image(systemName: "arrow.up") }.font(.subheadline.weight(.medium)).padding(.horizontal, 15).frame(minHeight: 44).background(Theme.blush, in: Capsule()) }.disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.asking).accessibilityIdentifier("ask-chef")
            }
        }.keyboardDone()
            .fullScreenCover(isPresented: $camera) { CompanionCamera { image = $0; camera = false } }
            .onChange(of: selection) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { image = UIImage(data: data) } } }
    }
}
