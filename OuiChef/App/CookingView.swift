import SwiftUI

struct CookingView: View {
    @Bindable var store: ChefStore
    @State private var showEnd = false
    @State private var showVoiceInfo = false
    @State private var command = ""

    var body: some View {
        if let session = store.session {
            Group {
                if !session.ready {
                    IngredientCheckView(store: store, onEnd: { showEnd = true })
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        HStack {
                            Text(session.finished ? "MADE WITH A LITTLE HELP" : "IN YOUR KITCHEN")
                                .font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(Theme.green)
                            Spacer()
                            Button { showEnd = true } label: { Image(systemName: "xmark.circle").font(.title3).frame(width: 44, height: 44) }.accessibilityLabel("End cooking session")
                        }
                        Text(session.recipe.title).font(Theme.serif(37))
                        HStack {
                            Label(session.recipe.style.name, systemImage: "leaf")
                            Spacer()
                            Text("\(session.recipe.yieldLabel.capitalized): \(session.servings)")
                        }.font(.caption).foregroundStyle(.secondary)
                        if session.finished {
                            VStack(spacing: 18) {
                                Image(systemName: "checkmark.seal").font(.system(size: 60, weight: .ultraLight)).foregroundStyle(Theme.green)
                                Text("You made it.").font(Theme.serif(33))
                                Text("Take a moment. Enjoy what you've made.").foregroundStyle(.secondary)
                                Button("Save this cooking session") { store.endSession() }.buttonStyle(FilledButton())
                            }.frame(maxWidth: .infinity).padding(.vertical, 35)
                        } else {
                            ProgressView(value: Double(session.completed.count), total: Double(session.recipe.nodes.count)).tint(Theme.green)
                            Text("\(session.completed.count) of \(session.recipe.nodes.count) tasks completed").font(.caption).foregroundStyle(.secondary)
                            if session.guidancePaused {
                                Label("Guidance paused · timers keep running", systemImage: "pause.circle").font(.subheadline).kitchenCard()
                                Button("Resume cooking") { store.resume() }.buttonStyle(FilledButton())
                            }
                            if let notice = store.notificationNotice { Label(notice, systemImage: "bell.slash").font(.caption).foregroundStyle(Theme.orange).kitchenCard() }
                            ForEach(session.activeNodes) { node in taskCard(node, session: session, active: true) }
                            if !session.eligibleNodes.isEmpty {
                                Text(session.activeNodes.isEmpty ? "Let's begin" : "While that cooks").font(Theme.serif(27))
                                ForEach(session.eligibleNodes) { node in taskCard(node, session: session, active: false) }
                            }
                            if !session.completed.isEmpty {
                                DisclosureGroup("Already done · \(session.completed.count)") {
                                    ForEach(session.recipe.nodes.filter { session.completed.contains($0.id) }) { node in
                                        Label(node.title, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Theme.green).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                                    }
                                }.kitchenCard()
                            }
                        }
                        voiceCard
                    }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 35)
                }
                }
            }
            .id(session.id)
            .confirmationDialog("End this cooking session?", isPresented: $showEnd, titleVisibility: .visible) {
                Button("End session and cancel its reminders", role: .destructive) { store.endSession() }
                Button("Keep cooking", role: .cancel) { }
            } message: { Text("\(session.timers.count) timer(s) still belong to this session. Ending the session does not stop heat, cooking, or proofing. Your progress will be saved to history.") }
            .sheet(isPresented: $showVoiceInfo) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Let's talk cooking.").font(Theme.serif(34))
                        Text("Cloud voice connects you to xAI for recipe questions, step check-ins, and confirmed ratio adjustments. Local voice supports a smaller set of cooking commands.")
                        Text("Try: start step, done, not yet, repeat, pause, resume, where are we, less talking, or stop listening.")
                        Text("Cloud voice sends audio and current recipe/preferences through our server to xAI. Oui Chef stores usage totals, not recordings or transcripts. Local recognition may use Apple's speech service. Voice stops when you leave the app.").font(.subheadline).foregroundStyle(.secondary)
                        VoiceSettingsView(store: store)
                        Spacer()
                    }.padding(26).background(Theme.cream).toolbar { Button("Done") { showVoiceInfo = false } }
                }.presentationDetents([.medium, .large])
            }
        }
    }

    private func taskCard(_ node: CookingNode, session: CookingSession, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(active ? "IN PROGRESS" : "READY WHEN YOU ARE").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(active ? Theme.orange : Theme.green)
                Spacer()
                Image(systemName: node.kind == .wait ? "timer" : "hand.draw").foregroundStyle(Theme.green)
            }
            Text(node.title).font(Theme.serif(29))
            Text(node.instruction).font(.subheadline).lineSpacing(4)
            if let timer = session.timers.first(where: { $0.nodeID == node.id }) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = timer.remaining(at: context.date)
                    HStack {
                        Image(systemName: "timer").font(.title2)
                        Text(duration(abs(remaining))).font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit()
                        Spacer()
                        Text(remaining > 0 ? "until we check" : "overdue · check now").font(.caption).multilineTextAlignment(.trailing)
                    }.foregroundStyle(remaining > 0 ? Theme.green : Theme.orange)
                }
            }
            if active {
                Label(node.criterion, systemImage: "sparkle").font(.subheadline).foregroundStyle(Theme.green)
                HStack {
                    Button("Not yet") { store.notYet(node) }.frame(minHeight: 44).frame(maxWidth: .infinity)
                    Button("Done") { store.complete(node) }.buttonStyle(FilledButton())
                        .accessibilityIdentifier("complete-\(node.id)")
                }.disabled(session.guidancePaused)
            } else {
                Button(node.kind == .checkpoint ? "Let's check" : "I've started") { store.begin(node) }
                    .buttonStyle(FilledButton()).disabled(session.guidancePaused || store.restriction(for: session.recipe) != nil)
            }
        }.kitchenCard()
    }
    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button { store.openVoice() } label: { VoiceOrb(size: 90) }
                    .accessibilityLabel("Start voice guidance")
                VStack(alignment: .leading, spacing: 6) {
                    Text("I'm here with you.").font(Theme.serif(23))
                    Text(store.voice.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { showVoiceInfo = true } label: { Image(systemName: "info.circle").frame(width: 40, height: 44) }.accessibilityLabel("About voice commands")
            }
            Text(store.chefMessage).font(.subheadline).lineSpacing(4)
            HStack {
                Button { store.openVoice() } label: { Label("Start voice", systemImage: "mic") }
                    .buttonStyle(.bordered).controlSize(.large)
                Spacer()
                if store.session?.ready == true && store.session?.finished == false {
                    Button { if store.session?.guidancePaused == true { store.resume() } else { store.pause() } } label: {
                        Image(systemName: store.session?.guidancePaused == true ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel(store.session?.guidancePaused == true ? "Resume guidance" : "Pause guidance")
                }
            }
            DisclosureGroup("Type a cooking command") {
                HStack {
                    TextField("e.g. repeat or where are we", text: $command).font(.subheadline).textFieldStyle(.roundedBorder).onSubmit(sendCommand)
                    Button(action: sendCommand) { Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44) }.accessibilityLabel("Send command")
                }.padding(.top, 8)
            }.font(.caption)
        }.kitchenCard()
    }
    private func sendCommand() { guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }; store.submitText(command); command = "" }
    private func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60)
    }
}
