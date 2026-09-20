import SwiftUI

struct VoiceSessionView: View {
    let store: ChefStore
    let transition: Namespace.ID
    @State private var showingPreparation = false
    private var voice: GuidedVoice { store.voice }

    private var title: String {
        if voice.isStarting || (voice.enabled && !voice.isListening) { return "Connecting" }
        if !voice.enabled { return "Microphone off" }
        if voice.isSpeaking { return "Your chef is speaking" }
        if voice.isResponding && !voice.hearingSpeech { return "One moment…" }
        return "Listening"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Oui Chef").font(Theme.serif(27)).padding(.top, 18).padding(.bottom, 12)
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        Spacer(minLength: 24)
                        VStack(spacing: 8) {
                            Text(title).font(.system(.largeTitle, design: .serif)).accessibilityAddTraits(.isHeader)
                            Text(voice.isListening ? (voice.isSpeaking ? "You can interrupt me anytime." : "I’m here — keep talking.") : "A little help, every step of the way.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        VoiceOrb(active: voice.isListening, size: min(260, geometry.size.width - 80))
                        Label(voice.isListening ? "Microphone on" : "Microphone off", systemImage: voice.isListening ? "mic.fill" : "mic.slash")
                            .font(.caption).foregroundStyle(voice.isListening ? Theme.green : .secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(voice.isListening ? "Microphone on" : "Microphone off")
                            .accessibilityIdentifier("microphone-state")
                        Button {
                            voice.stop()
                            store.showingVoice = false
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 26, weight: .light)).foregroundStyle(.white)
                                .frame(width: 66, height: 66)
                                .background(Color(red: 0.96, green: 0.25, blue: 0.13), in: Circle())
                        }
                        .matchedGeometryEffect(id: "voice-control", in: transition)
                        .accessibilityLabel("Close voice")
                        .accessibilityHint("Stops the microphone and returns to your kitchen. Timers keep running.")
                        Text("Tap to stop").font(.subheadline).foregroundStyle(.secondary)
                        if let session = store.session {
                            if session.finished {
                                Button("Take photo") { store.photoAttemptID = session.id }.buttonStyle(FilledButton())
                                Button("Save without a photo") { store.endSession(); store.showingVoice = false }
                            } else if session.pendingRecovery != nil { RecoveryView(store: store) }
                            else if !session.ready {
                                Button("Check ingredients on screen") { showingPreparation = true }
                            }
                        }
                        Spacer(minLength: 16)
                        if voice.isStarting || (voice.enabled && !voice.isListening) {
                            ProgressView().tint(Theme.green)
                        }
                        if !voice.isListening {
                            Text(voice.status).font(.subheadline).foregroundStyle(.secondary)
                                .accessibilityIdentifier("voice-status")
                            if voice.needsSettings {
                                Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                            } else if !voice.enabled && !voice.isStarting {
                                Button("Try again") { Task { await voice.start() } }
                            }
                            #if DEBUG
                            if voice.needsTesterAccess, let id = voice.testerID {
                                DisclosureGroup("Development tester ID") {
                                    Text(id).font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("development-tester-id")
                                    Button("Copy tester ID") { UIPasteboard.general.string = id }
                                }.font(.subheadline)
                            }
                            #endif
                        } else {
                            HStack(spacing: 16) {
                                Image(systemName: "leaf").font(.title2).foregroundStyle(Theme.green)
                                Text(store.session == nil ? "Tell me what you have, and I’ll suggest a recipe." : store.chefMessage)
                                    .font(.system(.subheadline, design: .serif)).italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("voice-status")
                            }
                            .padding(20).background(Theme.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .multilineTextAlignment(.center).padding(.horizontal, 28).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }.scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(Theme.ink)
        .task { await voice.start() }
        .sheet(isPresented: $showingPreparation) {
            NavigationStack {
                CookingView(store: store)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .principal) { Text("Oui Chef").font(Theme.serif(24)) } }
            }
        }
        .onChange(of: store.session?.ready) { _, ready in if ready == true { showingPreparation = false } }
        .onChange(of: store.session?.id) { _, id in showingPreparation = id != nil && store.session?.ready == false }
        .onDisappear { if !showingPreparation { voice.stop() } }
    }
}
