import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UserNotifications
import AVFoundation
import CryptoKit

private enum CompanionRequestError: Error { case conflict }

struct CompanionArchive: Codable {
    var profile = CookProfile()
    var recipes: [CompanionRecipe] = []
    var attempts: [CookAttempt] = []
    var activeID: String?
    var dirtyRecipes: Set<String> = []
    var dirtyAttempts: Set<String> = []
    var revisions: [String: Int] = [:]
    var profileDirty = false
    var pendingPhotos: Set<String> = []
}

@MainActor @Observable
final class CompanionStore {
    var archive = CompanionArchive()
    var imports: [RecipeImport] = []
    var uid: String?
    var error: String?
    var notice: String?
    var loading = false
    var importing = false
    var focusedImportID: String?
    var asking = false
    var deletingRecipeIDs: Set<String> = []
    var voiceEnabled = false
    var voiceStatus = "Tap to talk"
    var selectedRecipe: CompanionRecipe?
    var showImport = false
    var showCooking = false
    var showPhoto = false
    var videoURL: URL?
    var lastAnswer: String?
    var pendingURL = ""
    var foreground = true
    private var listeners: [ListenerRegistration] = []
    private var syncTask: Task<Void, Never>?
    private let voice = CloudVoice()
    private var voiceCalls = Set<String>()
    private var accountGeneration = UUID()
    private var fileURL: URL?
    private var tickTask: Task<Void,Never>?
    private var localTest = false
    private var notificationIDs: Set<String> = []
    private var lastReminderAt = 0.0
    private let db = Firestore.firestore()
    var profile: CookProfile { archive.profile }
    var recipes: [CompanionRecipe] { archive.recipes.sorted { $0.createdAt > $1.createdAt } }
    var active: CookAttempt? { archive.attempts.first { $0.id == archive.activeID } }
    var history: [CookAttempt] { archive.attempts.filter { $0.finishedAt != nil }.sorted { ($0.finishedAt ?? 0) > ($1.finishedAt ?? 0) } }
    var inProgress: [CookAttempt] { archive.attempts.filter { $0.finishedAt == nil } }
    static var now: Double { Date().timeIntervalSince1970 * 1000 }

    init() {
        voice.onEvent = { [weak self] event in self?.receiveVoice(event) }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.offerReminder()
                if self.foreground { self.sync() }
            }
        }
    }

    func switchAccount(_ accountID: String?) {
        stopVoice(); syncTask?.cancel(); syncTask = nil
        listeners.forEach { $0.remove() }; listeners = []
        accountGeneration = UUID(); uid = accountID; archive = CompanionArchive(); imports = []
        selectedRecipe = nil; focusedImportID = nil; showImport = false; importing = false; showCooking = false; lastAnswer = nil; error = nil; notice = nil
        deletingRecipeIDs = []
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(notificationIDs)); notificationIDs = []
        fileURL = nil
        #if DEBUG
        localTest = ProcessInfo.processInfo.arguments.contains("--companion-preview")
        if localTest { loadPreview(); return }
        #endif
        guard let accountID else { loading = false; return }
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Companion", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let key = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
            fileURL = directory.appendingPathComponent(key + ".json")
            if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) { archive = try JSONDecoder().decode(CompanionArchive.self, from: Data(contentsOf: fileURL)) }
        } catch { self.error = "Your local cookbook could not open: \(error.localizedDescription)" }
        let generation = accountGeneration
        loading = !archive.profile.onboardingComplete
        listeners.append(db.document("users/\(accountID)/settings/cooking").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.accountGeneration == generation else { return }
                self.loading = false
                if let payload = snapshot?.data()?["payload"] as? String, let profile = try? CompanionJSON.decode(CookProfile.self, payload), !self.archive.profileDirty { self.archive.profile = profile; self.persist() }
                if error != nil { self.notice = "Showing your saved kitchen. Cloud sync will retry." }
            }
        })
        for collection in ["cookbook", "cooks", "imports"] {
            // ponytail: 200 records per collection cover this three-tester beta; paginate before a larger launch.
            listeners.append(db.collection("users/\(accountID)/\(collection)").order(by: collection == "imports" ? "createdAt" : "updatedAt", descending: true).limit(to: 200).addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.accountGeneration == generation else { return }
                    guard let docs = snapshot?.documents else { if error != nil { self.notice = "Cloud sync is pending. Your local changes are saved." }; return }
                    if collection == "imports" {
                        self.imports = docs.compactMap { doc in
                            let d = doc.data()
                            guard let url = d["url"] as? String, let status = d["status"] as? String else { return nil }
                            return RecipeImport(id: doc.documentID, url: url, status: status, message: d["message"] as? String ?? "", recipeID: d["recipeID"] as? String, createdAt: (d["createdAt"] as? NSNumber)?.doubleValue ?? 0, source: d["source"] as? String ?? "Website", stage: (d["stage"] as? NSNumber)?.intValue, attempt: (d["attempt"] as? NSNumber)?.intValue, previewTitle: d["previewTitle"] as? String, previewCreator: d["previewCreator"] as? String, previewSummary: d["previewSummary"] as? String, previewIngredients: d["previewIngredients"] as? [String], previewSteps: d["previewSteps"] as? [String], sourceTitle: d["sourceTitle"] as? String, sourceDurationSeconds: (d["sourceDurationSeconds"] as? NSNumber)?.doubleValue, sourceExtractor: d["sourceExtractor"] as? String, recipeTitle: d["recipeTitle"] as? String, originalTranscript: d["originalTranscript"] as? String, transcriptLanguage: d["transcriptLanguage"] as? String, translatedTranscript: d["translatedTranscript"] as? String, videoObservations: d["videoObservations"] as? String, frameSeconds: (d["frameSeconds"] as? [NSNumber])?.map(\.doubleValue), extractionReason: d["extractionReason"] as? String, failurePoint: d["failurePoint"] as? String, sourceText: d["sourceText"] as? String, retrieval: (d["retrieval"] as? [String: Any]).flatMap { try? String(data: JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8) }, retrievalErrors: d["retrievalErrors"] as? [String], scopeReason: d["scopeReason"] as? String, cacheHit: d["cacheHit"] as? Bool)
                        }
                    } else {
                        for doc in docs {
                            if collection == "cookbook", doc.data()["deleted"] as? Bool == true {
                                self.archive.recipes.removeAll { $0.id == doc.documentID }
                                self.archive.dirtyRecipes.remove(doc.documentID)
                                if self.selectedRecipe?.id == doc.documentID { self.selectedRecipe = nil }
                                continue
                            }
                            guard let payload = doc.data()["payload"] as? String else { continue }
                            if collection == "cookbook", !self.archive.dirtyRecipes.contains(doc.documentID), let recipe = try? CompanionJSON.decode(CompanionRecipe.self, payload), (try? recipe.validate()) != nil {
                                self.archive.recipes.removeAll { $0.id == recipe.id }; self.archive.recipes.append(recipe)
                            } else if collection == "cooks", !self.archive.dirtyAttempts.contains(doc.documentID), let attempt = try? CompanionJSON.decode(CookAttempt.self, payload), (try? attempt.recipe.validate()) != nil {
                                self.archive.attempts.removeAll { $0.id == attempt.id }; self.archive.attempts.append(attempt)
                                self.archive.revisions[attempt.id] = doc.data()["revision"] as? Int ?? 0
                            }
                        }
                        self.persist(); self.scheduleTimers()
                    }
                }
            })
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.accountGeneration == generation else { return }
            self.loading = false
        }
        scheduleTimers(); sync(); consumeSharedLinks()
    }

    @discardableResult func persist() -> Bool {
        guard !localTest else { return true }
        guard let fileURL else { return false }
        do { try JSONEncoder().encode(archive).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); return true }
        catch { self.error = "Your changes could not be saved: \(error.localizedDescription)"; return false }
    }
    func setProfile(_ profile: CookProfile) { archive.profile = profile; archive.profileDirty = true; if persist() { sync() } }
    func saveRecipe(_ recipe: CompanionRecipe) {
        guard !deletingRecipeIDs.contains(recipe.id) else { return }
        archive.recipes.removeAll { $0.id == recipe.id }; archive.recipes.append(recipe); archive.dirtyRecipes.insert(recipe.id)
        if persist() { sync() }
    }
    func deleteRecipe(_ id: String) async {
        guard deletingRecipeIDs.insert(id).inserted else { return }
        let generation = accountGeneration
        defer { if accountGeneration == generation { deletingRecipeIDs.remove(id) } }
        do {
            // Finish an in-flight save before deleting so it cannot recreate this recipe.
            await syncTask?.value
            guard accountGeneration == generation else { return }
            if !localTest { _ = try await request("delete-recipe", body: ["id": id]) }
            archive.recipes.removeAll { $0.id == id }; archive.dirtyRecipes.remove(id)
            imports.removeAll { $0.id == id || $0.recipeID == id }
            if selectedRecipe?.id == id { selectedRecipe = nil }
            persist()
        } catch {
            if accountGeneration == generation { self.error = "Could not delete the recipe. \(error.localizedDescription)" }
        }
    }
    func start(_ recipe: CompanionRecipe) {
        do {
            try recipe.validate()
            var saved = recipe; saved.reviewed = true; saveRecipe(saved)
            let attempt = CookAttempt(recipe: saved)
            archive.attempts.append(attempt); archive.activeID = attempt.id; archive.dirtyAttempts.insert(attempt.id)
            guard persist() else { return }
            selectedRecipe = nil; showCooking = true; lastAnswer = nil; sync()
        } catch { self.error = error.localizedDescription }
    }
    func resume(_ id: String) { stopVoice(); archive.activeID = id; showCooking = true; lastAnswer = nil; persist() }
    func act(_ operation: String, target: String? = nil, seconds: Double? = nil, text: String? = nil) {
        guard let active else { return }
        do { try apply(CookAction(operation: operation, sessionID: active.id, revision: active.revision, target: target, seconds: seconds, text: text)) }
        catch { self.error = error.localizedDescription }
    }
    private func apply(_ action: CookAction) throws {
        guard let index = archive.attempts.firstIndex(where: { $0.id == action.sessionID }), action.sessionID == archive.activeID else { throw CookingError.invalid("Open this cooking session first.") }
        let previous = archive
        var next = archive.attempts[index]
        try next.apply(action, at: Self.now)
        archive.attempts[index] = next; archive.dirtyAttempts.insert(next.id)
        guard persist() else { archive = previous; throw CookingError.invalid("Your change could not be saved.") }
        scheduleTimers(); sync()
        if next.finishedAt != nil { stopVoice() }
        else if voiceEnabled { voice.send(["type": "context", "context": voiceContext()]) }
    }
    func updateAttempt(_ id: String, edit: (inout CookAttempt) -> Void) {
        guard let index = archive.attempts.firstIndex(where: { $0.id == id }) else { return }
        edit(&archive.attempts[index]); archive.dirtyAttempts.insert(id); if persist() { sync() }
    }

    func request(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let uid, let user = Auth.auth().currentUser, user.uid == uid,
              let endpoint = CloudVoiceAccount.endpoint, var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw CookingError.invalid("Sign in to continue.") }
        let generation = accountGeneration
        url.scheme = "https"; url.path = "/companion/\(path)"
        var request = URLRequest(url: url.url!); request.httpMethod = "POST"; request.timeoutInterval = path == "question" ? 150 : 25
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data,response) = try await URLSession.shared.data(for: request)
        guard accountGeneration == generation else { throw CancellationError() }
        let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (response as? HTTPURLResponse)?.statusCode == 409 { throw CompanionRequestError.conflict }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CookingError.invalid(result["error"] as? String ?? "The cooking service is unavailable. Please retry.") }
        return result
    }
    func importRecipe(_ raw: String, text: String = "") async {
        guard !importing else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : Self.sharedURL(raw)
        guard let url, !url.isEmpty || !text.isEmpty else { error = "Paste a recipe link or ingredients and steps."; return }
        guard text.count <= 40000 else { error = "Keep recipe text under 40,000 characters."; return }
        importing = true; defer { importing = false }
        do {
            let result = try await request("import", body: ["url": url, "text": text])
            guard let id = result["id"] as? String else { throw CookingError.invalid("The import could not be started. Please retry.") }
            focusedImportID = id
            if result["existing"] as? Bool != true { imports.removeAll { $0.id == id && $0.attempt != result["attempt"] as? Int } }
            if !imports.contains(where: { $0.id == id }) {
                imports.insert(RecipeImport(id: id, url: url, status: "queued", message: "Waiting to read your recipe…", createdAt: Self.now, source: url.isEmpty ? "Pasted text" : "Recipe link", attempt: result["attempt"] as? Int), at: 0)
            }
            pendingURL = ""
        }
        catch { self.error = error.localizedDescription }
    }
    func cancelImport(_ id: String) async { do { _ = try await request("cancel", body: ["id": id]) } catch { self.error = error.localizedDescription } }
    static func sharedURL(_ text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue), let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let url = match.url, ["https", "http"].contains(url.scheme ?? ""), url.host != nil else { return nil }
        return url.absoluteString
    }
    func consumeSharedLinks() {
        guard uid != nil, let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.xie.ouichef")?.appendingPathComponent("imports") else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let ownedFiles = files.filter { file in
            guard let data = try? Data(contentsOf: file), let item = try? JSONSerialization.jsonObject(with: data) as? [String:String] else { return false }
            return item["ownerUID", default: ""].isEmpty || item["ownerUID"] == uid
        }
        if let file = ownedFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first, let data = try? Data(contentsOf: file), let item = try? JSONSerialization.jsonObject(with: data) as? [String: String], let url = item["url"] {
            pendingURL = url; showImport = true
            // Remove only after the backend accepts this particular item.
            Task {
                do { let result = try await request("import", body: ["url": url]); focusedImportID = result["id"] as? String; try FileManager.default.removeItem(at: file); pendingURL = ""; consumeSharedLinks() }
                catch { notice = "Your shared link is saved. Tap Import to try again." }
            }
        }
    }

    func sync() {
        guard syncTask == nil, let uid, !localTest else { return }
        let generation = accountGeneration
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { if accountGeneration == generation { syncTask = nil } }
            do {
                if archive.profileDirty {
                    let snapshot = archive.profile
                    try await db.document("users/\(uid)/settings/cooking").setData(["payload": try CompanionJSON.encode(snapshot), "updatedAt": Self.now])
                    guard accountGeneration == generation, !Task.isCancelled else { return }
                    if snapshot == archive.profile { archive.profileDirty = false }
                }
                for id in archive.dirtyRecipes {
                    guard !deletingRecipeIDs.contains(id) else { continue }
                    guard let recipe = archive.recipes.first(where: { $0.id == id }) else { continue }
                    try await db.document("users/\(uid)/cookbook/\(id)").setData(["id": id, "payload": try CompanionJSON.encode(recipe), "updatedAt": Self.now])
                    guard accountGeneration == generation, !Task.isCancelled else { return }
                    if recipe == archive.recipes.first(where: { $0.id == id }) { archive.dirtyRecipes.remove(id) }
                }
                for id in archive.pendingPhotos {
                    guard let attempt = archive.attempts.first(where: { $0.id == id }), let file = attempt.photoFile else { continue }
                    let data = try Data(contentsOf: photoURL(file)); let path = "users/\(uid)/cooks/\(id)/dish.jpg"
                    let metadata = StorageMetadata(); metadata.contentType = "image/jpeg"
                    _ = try await Storage.storage().reference().child(path).putDataAsync(data, metadata: metadata)
                    guard accountGeneration == generation, !Task.isCancelled else { return }
                    if let index = archive.attempts.firstIndex(where: { $0.id == id && $0.photoFile == file }) {
                        archive.attempts[index].photoPath = path; archive.pendingPhotos.remove(id); archive.dirtyAttempts.insert(id)
                    }
                }
                for id in archive.dirtyAttempts {
                    guard let attempt = archive.attempts.first(where: { $0.id == id }) else { continue }
                    do {
                        let response = try await request("sync", body: ["id": id, "payload": try CompanionJSON.encode(attempt), "expectedRevision": archive.revisions[id] ?? 0])
                        guard accountGeneration == generation, !Task.isCancelled else { return }
                        archive.revisions[id] = response["revision"] as? Int ?? 0
                        if attempt == archive.attempts.first(where: { $0.id == id }) { archive.dirtyAttempts.remove(id) }
                    } catch CompanionRequestError.conflict {
                        // Preserve both cooks when two devices have changed the same attempt.
                        guard let current = archive.attempts.first(where: { $0.id == id }) else { continue }
                        var recovered = current; recovered.id = UUID().uuidString
                        recovered.changes.append("Continued as a separate attempt after changes on another device.")
                        archive.attempts.removeAll { $0.id == id }; archive.attempts.append(recovered)
                        archive.dirtyAttempts.remove(id); archive.dirtyAttempts.insert(recovered.id); archive.revisions[id] = nil
                        if archive.activeID == id { archive.activeID = recovered.id; stopVoice() }
                        notice = "This cook changed on another device. Both attempts are preserved."
                        persist(); scheduleTimers(); return
                    }
                }
                notice = nil; persist()
            } catch {
                guard accountGeneration == generation, !Task.isCancelled else { return }
                notice = "Saved on this iPhone. \(error.localizedDescription)"; persist()
            }
        }
    }
    func scheduleTimers() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Array(notificationIDs)); notificationIDs = []
        for attempt in archive.attempts where attempt.finishedAt == nil {
            for timer in attempt.timers where !timer.acknowledged && timer.pausedSeconds == nil && timer.deadline > Self.now {
                let identifier = "cook-\(attempt.id)-\(timer.id)"; notificationIDs.insert(identifier)
                let content = UNMutableNotificationContent(); content.title = "\(attempt.recipe.title) · \(timer.label)"; content.body = timer.cue
                content.sound = .default; content.userInfo = ["attemptID": attempt.id]
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.remaining(at: Self.now)), repeats: false)))
            }
        }
    }
    func enableNotifications() async {
        guard !localTest else { return }
        do { if !((try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound])) ) { notice = "Timer alerts are off. Enable notifications in Settings for lock-screen reminders." }; scheduleTimers() }
        catch { notice = "Timer alerts could not be enabled." }
    }
    private func offerReminder() {
        guard foreground, voiceEnabled, profile.gentleGuidance, let active, !active.guidancePaused, active.finishedAt == nil else { return }
        guard Self.now - lastReminderAt > 30000 else { return }
        let timer = active.timers.first { $0.expired(at: Self.now) && !active.deliveredReminders.contains($0.id) }
        if let timer {
            updateAttempt(active.id) { $0.deliveredReminders.append(timer.id) }
            lastReminderAt = Self.now
            voice.send(["type": "cue", "text": "The \(timer.label) timer ended. \(timer.cue) Ask whether it is ready; do not mark complete."])
        } else if let reminder = active.currentStep.reminder, !active.deliveredReminders.contains("step:" + active.currentStep.id) {
            updateAttempt(active.id) { $0.deliveredReminders.append("step:" + active.currentStep.id) }
            lastReminderAt = Self.now
            voice.send(["type": "cue", "text": reminder])
        }
    }

    func ask(_ question: String, recipe: CompanionRecipe, image: Data? = nil) async {
        guard !asking else { return }; asking = true; lastAnswer = nil; defer { asking = false }
        let attemptID = active?.recipe.id == recipe.id ? active?.id : nil
        if let attemptID { updateAttempt(attemptID) { $0.messages.append(CookingMessage(role: "user", text: question)) } }
        do {
            var body: [String: Any] = ["question": question, "recipe": try json(recipe), "profile": try json(profile), "history": historyContext(recipeID: recipe.id)]
            if let attemptID, let attempt = archive.attempts.first(where: { $0.id == attemptID }) { var state = try json(attempt) as? [String:Any] ?? [:]; state.removeValue(forKey: "recipe"); body["session"] = state }
            if let image { body["image"] = "data:image/jpeg;base64,\(image.base64EncodedString())" }
            let result = try await request("question", body: body)
            let answer = result["answer"] as? String ?? "Please try your question again."; lastAnswer = answer
            if let attemptID { updateAttempt(attemptID) { $0.messages.append(CookingMessage(role: "assistant", text: answer)) } }
        } catch { self.error = error.localizedDescription }
    }
    private func json<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    private func historyContext(recipeID: String) -> [[String:Any]] {
        history.filter { $0.recipe.id == recipeID }.prefix(3).map {
            ["date": $0.finishedAt ?? 0, "changes": $0.changes, "notes": $0.notes, "recipeTemperatures": $0.recipe.steps.compactMap { $0.temperature }, "completedSteps": $0.completed, "durationMinutes": (($0.finishedAt ?? $0.startedAt) - $0.startedAt) / 60000] as [String:Any]
        }
    }
    private func voiceContext() -> [String: Any] {
        var context: [String: Any] = ["companionVersion": 2, "profile": (try? json(profile)) ?? [:]]
        if var attempt = active {
            attempt.messages = Array(attempt.messages.suffix(8)); attempt.events = Array(attempt.events.suffix(100))
            context["session"] = (try? json(attempt)) ?? [:]
            context["history"] = historyContext(recipeID: attempt.recipe.id)
        }
        return context
    }
    func toggleVoice() {
        if voiceEnabled { stopVoice(); return }
        guard active?.finishedAt == nil, active != nil else { return }
        let generation = accountGeneration, sessionID = active?.id
        Task {
            guard await AVAudioApplication.requestRecordPermission() else { error = "Enable microphone access in Settings to talk while cooking."; return }
            guard accountGeneration == generation, active?.id == sessionID, foreground, showCooking else { return }
            voiceEnabled = true; voiceStatus = "Connecting…"; voiceCalls = []
            do { try await voice.start(context: voiceContext()) }
            catch { stopVoice(); self.error = error.localizedDescription }
        }
    }
    func stopVoice() { voice.stop(); voiceEnabled = false; voiceStatus = "Tap to talk" }
    private func receiveVoice(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "ready": voiceStatus = "Listening…"
        case "responding": voiceStatus = "Your chef is speaking"
        case "playback_finished": if voiceEnabled { voiceStatus = "Listening…" }
        case "ended", "error": notice = event["message"] as? String; stopVoice()
        case "transcript":
            if let text = event["text"] as? String, !text.isEmpty, let active {
                updateAttempt(active.id) { $0.messages.append(CookingMessage(role: event["role"] as? String ?? "assistant", text: text)) }
                if event["role"] as? String == "assistant" { lastAnswer = text }
            }
        case "tool":
            guard let callID = event["callID"] as? String, !voiceCalls.contains(callID) else { return }; voiceCalls.insert(callID)
            var result: [String: Any]
            do {
                guard let arguments = event["arguments"] as? String, let object = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any], let operation = object["operation"] as? String else { throw CookingError.invalid("Invalid cooking request.") }
                if operation == "state" { result = voiceContext() }
                else if operation == "show_video" { showTechnique(stepID: object["target"] as? String); result = ["ok": videoURL != nil] }
                else {
                    guard object["confirmed"] as? Bool == true else { throw CookingError.invalid("Confirm the cooking action first.") }
                    var payload = object; payload["id"] = callID
                    let action = try JSONDecoder().decode(CookAction.self, from: JSONSerialization.data(withJSONObject: payload))
                    try apply(action); result = ["ok": true, "state": voiceContext()]
                }
            } catch { result = ["ok": false, "error": error.localizedDescription, "state": voiceContext()] }
            voice.send(["type": "tool_result", "callID": callID, "output": (try? JSONSerialization.data(withJSONObject: result)).map { String(decoding: $0, as: UTF8.self) } ?? "{}", "context": voiceContext()])
        default: break
        }
    }
    func showTechnique(stepID: String? = nil) {
        guard let attempt = active, var url = URLComponents(string: attempt.recipe.sourceURL) else { return }
        guard let step = stepID.flatMap({ id in attempt.recipe.steps.first { $0.id == id } }) ?? (stepID == nil ? attempt.currentStep : nil) else { error = "That technique was not found in this recipe."; return }
        if attempt.recipe.sourceName == "YouTube", let seconds = step.videoSeconds { url.queryItems = (url.queryItems ?? []).filter { $0.name != "t" } + [URLQueryItem(name: "t", value: "\(Int(seconds))s")] }
        stopVoice(); videoURL = url.url
    }
    func background() { foreground = false; stopVoice(); persist(); scheduleTimers() }
    func photoURL(_ name: String) -> URL { (fileURL?.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory).appendingPathComponent(name) }
    func attachPhoto(_ image: UIImage, attemptID: String) {
        guard let data = DishPhotoView.compressed(image) else { error = "This photo could not be saved."; return }
        do {
            let name = UUID().uuidString + ".jpg"; try data.write(to: photoURL(name), options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            archive.pendingPhotos.insert(attemptID); updateAttempt(attemptID) { $0.photoFile = name }; showPhoto = false
        } catch { self.error = "This photo could not be saved." }
    }
    func loadPhoto(_ attempt: CookAttempt) async -> UIImage? {
        if let file = attempt.photoFile, let image = UIImage(contentsOfFile: photoURL(file).path) { return image }
        guard let uid, let path = attempt.photoPath, path == "users/\(uid)/cooks/\(attempt.id)/dish.jpg" else { return nil }
        let generation = accountGeneration
        guard let data = try? await Storage.storage().reference().child(path).data(maxSize: 2_000_000), generation == accountGeneration else { return nil }
        return UIImage(data: data)
    }
    func deleteAccountData(_ uid: String) async throws {
        guard self.uid == uid else { throw CookingError.invalid("Account changed.") }
        syncTask?.cancel(); stopVoice()
        _ = try await request("delete-account-data", body: [:])
        for attempt in archive.attempts { if let file = attempt.photoFile { try? FileManager.default.removeItem(at: photoURL(file)) } }
        if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.xie.ouichef")?.appendingPathComponent("imports"), let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files {
                if let data = try? Data(contentsOf: file), let item = try? JSONSerialization.jsonObject(with: data) as? [String:String], item["ownerUID"] == uid { try FileManager.default.removeItem(at: file) }
            }
        }
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        archive = CompanionArchive()
    }
    #if DEBUG
    private func loadPreview() {
        uid = "preview"; loading = false; archive.profile.onboardingComplete = !ProcessInfo.processInfo.arguments.contains("--companion-onboarding")
        let recipe = CompanionRecipe(id: "preview-pasta", title: "Creamy garlic pasta", summary: "Simple ingredients. A little kitchen magic.", sourceURL: "https://example.com/recipe", sourceName: "Sample recipe", creator: "Oui Chef · preview", servings: 2, prepMinutes: 10, cookMinutes: 15, totalMinutes: 25,
            ingredients: [RecipeIngredient(id: "pasta", name: "Tagliatelle", quantity: "225 g", amount: 225, unit: "g"), RecipeIngredient(id: "garlic", name: "Garlic", quantity: "6 cloves"), RecipeIngredient(id: "cream", name: "Heavy cream", quantity: "1 cup"), RecipeIngredient(id: "parmesan", name: "Parmesan", quantity: "½ cup, grated"), RecipeIngredient(id: "oil", name: "Olive oil", quantity: "2 tbsp", pantry: true)],
            preparation: ["Peel and finely mince the garlic.", "Grate the parmesan."],
            steps: [RecipeStep(id: "boil", title: "Get the pasta going", instruction: "Bring a large pan of salted water to a boil. Add the pasta and cook according to the packet.", stage: "Cook the pasta", ingredients: [StepIngredient(ingredientID: "pasta", quantity: "225 g")], visualCue: "The pasta should be tender with a little bite."), RecipeStep(id: "garlic", title: "Sauté the garlic", instruction: "Warm the olive oil over medium heat. Add the garlic and stir gently until fragrant and just golden.", stage: "Make the sauce", ingredients: [StepIngredient(ingredientID: "garlic", quantity: "6 cloves, minced"), StepIngredient(ingredientID: "oil", quantity: "2 tbsp")], durationSeconds: 90, visualCue: "Lightly golden, not brown."), RecipeStep(id: "finish", title: "Bring it all together", instruction: "Add the cream, then stir in the parmesan and drained pasta. Loosen with a splash of pasta water if needed.", stage: "Finish & serve", ingredients: [StepIngredient(ingredientID: "cream", quantity: "1 cup"), StepIngredient(ingredientID: "parmesan", quantity: "½ cup")], visualCue: "A silky sauce that coats every strand.")], reviewed: true)
        archive.recipes = [recipe]
        if ProcessInfo.processInfo.arguments.contains("--companion-import-progress") {
            imports = [RecipeImport(id: "preview-import", url: "https://youtu.be/W_-D8PZwtSY", status: "extracting", message: "Completing the recipe while preserving its written instructions…", createdAt: Self.now, source: "YouTube", stage: 3, previewTitle: "Matcha Streusel Bread", previewCreator: "All Cooking Stuff", previewIngredients: ["415 g bread flour", "5 g matcha powder"], sourceTitle: "Matcha Streusel Bread", sourceDurationSeconds: 306, sourceExtractor: "YouTube", recipeTitle: "Matcha Streusel Bread", originalTranscript: "[58.6s] 第一步，准备面团。", transcriptLanguage: "zh-CN", translatedTranscript: "[58.6s] Step one: prepare the dough.", frameSeconds: [10, 30, 50], extractionReason: "The written description did not include all cooking steps.", failurePoint: "Written source")]
        } else if ProcessInfo.processInfo.arguments.contains("--companion-import-ready") {
            imports = [RecipeImport(id: "preview-import", url: "https://youtu.be/W_-D8PZwtSY", status: "ready", message: "Your recipe is ready.", recipeID: recipe.id, createdAt: Self.now, source: "YouTube", previewTitle: recipe.title, previewIngredients: ["225 g pasta"], previewSteps: ["Boil the pasta"])]; focusedImportID = "preview-import"; showImport = true
        }
    }
    #endif
}
