import SwiftUI
import FirebaseFirestore

extension ChefStore {
    @discardableResult
    func offerCompletionPhoto() -> Bool {
        guard let current = session, current.finished, current.photoInvitationOffered != true else { return false }
        guard updateSession({ $0.photoInvitationOffered = true }) else { return false }
        say("You made it! Would you like to take a picture for your cooking history? You can also add one later.")
        return true
    }

    @discardableResult
    func attachPhoto(_ data: Data, to id: UUID) -> Bool {
        guard archive.dishes.contains(where: { $0.id == id }) else { return false }
        do {
            let file = try storage.savePhoto(data)
            let old = archive.dishes.first { $0.id == id }?.photoFile
            guard commit({ next in
                guard let index = next.completedDishes?.firstIndex(where: { $0.id == id }) else { return }
                next.completedDishes?[index].photoFile = file
                next.completedDishes?[index].photoVersion = UUID().uuidString
                next.completedDishes?[index].deletePhoto = false
                next.completedDishes?[index].needsUpload = true
            }) else { try? FileManager.default.removeItem(at: storage.photoURL(file)); return false }
            if let old { try? FileManager.default.removeItem(at: storage.photoURL(old)) }
            syncDishes()
            return true
        } catch { self.error = "The photo could not be saved: \(error.localizedDescription)"; return false }
    }

    func removeDishPhoto(_ id: UUID) {
        let old = archive.dishes.first { $0.id == id }?.photoFile
        if commit({ next in
            guard let index = next.completedDishes?.firstIndex(where: { $0.id == id }) else { return }
            next.completedDishes?[index].photoFile = nil; next.completedDishes?[index].photoPath = nil
            next.completedDishes?[index].photoVersion = nil; next.completedDishes?[index].deletePhoto = true
            next.completedDishes?[index].needsUpload = true
        }) {
            if let old { try? FileManager.default.removeItem(at: storage.photoURL(old)) }
            syncDishes()
        }
    }

    func deleteDish(_ id: UUID) {
        let old = archive.dishes.first { $0.id == id }?.photoFile
        if commit({ next in
            next.completedDishes?.removeAll { $0.id == id }
            next.history.removeAll { $0.id == id }
            if next.deletedDishIDs == nil { next.deletedDishIDs = [] }
            if next.hiddenDishIDs == nil { next.hiddenDishIDs = [] }
            next.deletedDishIDs?.insert(id); next.hiddenDishIDs?.insert(id)
        }) {
            if let old { try? FileManager.default.removeItem(at: storage.photoURL(old)) }
            syncDishes()
        }
    }

    func syncDishes() {
        guard let uid = accountID, dishSyncTask == nil, !deletingAccount else { return }
        let generation = dishGeneration
        dishSyncTask = Task { [weak self] in
            guard let self else { return }
            // One serial uploader per account; new local edits stay dirty until their own upload finishes.
            defer { if self.dishGeneration == generation { self.dishSyncTask = nil } }
            do {
                while self.dishGeneration == generation && !Task.isCancelled {
                    if let id = self.archive.deletedDishIDs?.first {
                        try await self.dishCloud.delete(id, uid: uid)
                        guard self.dishGeneration == generation, !Task.isCancelled else { return }
                        guard self.commit({ next in
                            next.deletedDishIDs?.remove(id)
                            if let index = next.completedDishes?.firstIndex(where: { $0.id == id && $0.inProgress == true }) {
                                next.completedDishes?[index].photoPath = nil
                            }
                        }) else { return }
                    } else if let dish = self.archive.dishes.first(where: \.needsUpload) {
                        let image = try dish.photoFile.map { try Data(contentsOf: self.storage.photoURL($0)) }
                        let path = try await self.dishCloud.save(dish, uid: uid, image: image)
                        guard self.dishGeneration == generation, !Task.isCancelled else { return }
                        guard self.commit({ next in
                            guard let index = next.completedDishes?.firstIndex(where: { $0.id == dish.id }), next.completedDishes?[index] == dish else { return }
                            next.completedDishes?[index].photoPath = path
                            next.completedDishes?[index].needsUpload = false
                            next.completedDishes?[index].deletePhoto = nil
                        }) else { return }
                    } else { self.dishNotice = nil; return }
                }
            } catch {
                if self.dishGeneration == generation && !Task.isCancelled { self.dishNotice = "Saved on this iPhone. Cloud sync is pending; retry when connected." }
            }
        }
    }

    func loadDishes(more: Bool = false) async {
        guard let uid = accountID, !loadingDishes, !deletingAccount else { return }
        let generation = dishGeneration
        let localAtRead = archive.completedDishes ?? []
        loadingDishes = true
        defer { if dishGeneration == generation { loadingDishes = false } }
        do {
            let upperBound = more ? (dishCursor?.data()?["completedAt"] as? Timestamp)?.dateValue() ?? .distantPast : Date.distantFuture
            let (dishes, cursor) = try await dishCloud.page(uid, after: more ? dishCursor : nil)
            guard dishGeneration == generation, !Task.isCancelled else { return }
            let lowerBound = cursor == nil ? Date.distantPast : dishes.last?.completedAt ?? .distantFuture
            let remoteIDs = Set(dishes.map(\.id))
            let removed = localAtRead.filter { !$0.needsUpload && $0.inProgress != true && $0.completedAt > lowerBound && $0.completedAt < upperBound && !remoteIDs.contains($0.id) && archive.dishes.contains($0) }
            let removedIDs = Set(removed.map(\.id))
            let saved = commit { next in
                if next.completedDishes == nil { next.completedDishes = [] }
                // A deletion on another device must not be recreated from local cooking history.
                next.completedDishes?.removeAll { removedIDs.contains($0.id) }
                if next.hiddenDishIDs == nil { next.hiddenDishIDs = [] }
                next.hiddenDishIDs?.formUnion(removedIDs)
                for var dish in dishes where !(next.deletedDishIDs ?? []).contains(dish.id) && !(next.hiddenDishIDs ?? []).contains(dish.id) {
                    if let index = next.completedDishes?.firstIndex(where: { $0.id == dish.id }) {
                        guard next.completedDishes?[index].needsUpload != true, next.completedDishes?[index] == localAtRead.first(where: { $0.id == dish.id }) else { continue }
                        if next.completedDishes?[index].photoVersion == dish.photoVersion { dish.photoFile = next.completedDishes?[index].photoFile }
                        next.completedDishes?[index] = dish
                    } else { next.completedDishes?.append(dish) }
                }
            }
            if saved {
                for dish in removed { if let file = dish.photoFile { try? FileManager.default.removeItem(at: storage.photoURL(file)) } }
                dishCursor = cursor; hasMoreDishes = cursor != nil
            }
        } catch { if dishGeneration == generation { dishNotice = "Showing saved dishes. Pull down to refresh when connected." } }
        syncDishes()
    }

    func resumeAttempt(_ id: UUID) {
        guard let saved = archive.history.first(where: { $0.id == id }), !saved.finished else { return }
        if commit({ next in
            next.activate(saved); next.session?.guidancePaused = false
            next.session?.record("attempt_resumed", at: Date())
        }) {
            resetVoiceActions(); refreshTimers(); syncDishes()
            if let library = saved.ingredientLibrary { mergeLibrary(library) }
            say(saved.resumeMessage(at: Date()))
        }
    }

    func dismissParkedTimers(_ id: UUID) {
        _ = commit { next in
            guard let index = next.history.firstIndex(where: { $0.id == id }) else { return }
            next.history[index].timers = []
            next.history[index].record("timers_dismissed", at: Date())
        }
        refreshTimers()
    }
}

struct CompletedDishCard: View {
    let store: ChefStore
    let dish: CompletedDish
    @State private var image: UIImage?
    @State private var confirmDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image { Image(uiImage: image).resizable().scaledToFill().frame(height: 180).clipped().accessibilityLabel("Your \(dish.title)") }
            else { Label(dish.photoPath == nil ? "Add a photo of your dish" : "Dish photo", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 80).foregroundStyle(.secondary) }
            Text(dish.title).font(Theme.serif(24))
            Text(dish.completedAt, style: .date).font(.caption)
            Text("\(dish.chefName) · \(dish.servings) serving(s)").font(.caption).foregroundStyle(.secondary)
            if !dish.adjustments.isEmpty {
                DisclosureGroup("Your adjustments") { ForEach(Array(dish.adjustments.enumerated()), id: \.offset) { _, text in Text(text).font(.caption) } }
            }
            HStack {
                Button(dish.photoFile == nil && dish.photoPath == nil ? "Add photo" : "Replace photo") { store.photoAttemptID = dish.id }
                Spacer()
                Menu {
                    if dish.photoFile != nil || dish.photoPath != nil { Button("Remove photo", role: .destructive) { store.removeDishPhoto(dish.id) } }
                    Button("Delete completed dish", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Dish options")
            }
            if dish.needsUpload { Text(store.accountID == nil ? "Saved on this iPhone" : "Waiting to sync").font(.caption2).foregroundStyle(.secondary) }
        }.kitchenCard()
        .confirmationDialog("Delete this completed dish and its photo?", isPresented: $confirmDelete) {
            Button("Delete completed dish", role: .destructive) { store.deleteDish(dish.id) }
        }
        .task(id: "\(store.accountID ?? "guest"):\(dish.photoVersion ?? "none"):\(dish.photoFile ?? "")") {
            image = nil
            if let name = dish.photoFile { image = UIImage(contentsOfFile: store.storage.photoURL(name).path) }
            if image == nil, let uid = store.accountID, let data = try? await store.dishCloud.image(dish, uid: uid), !Task.isCancelled, store.accountID == uid { image = UIImage(data: data) }
        }
    }
}
