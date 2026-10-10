import SwiftUI
import PhotosUI
import AVFoundation

struct CompanionCompletion: View {
    @Bindable var store: CompanionStore
    let attempt: CookAttempt
    @State private var expanded = false
    @State private var image: UIImage?
    @State private var saved = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ZStack(alignment: .bottomTrailing) {
                    Group { if let image { Image(uiImage: image).resizable().scaledToFill() } else { RecipePhoto(recipe: attempt.recipe) } }.frame(height: 285).clipped().clipShape(RoundedRectangle(cornerRadius: 24))
                    if image == nil { Text("Recipe photo").font(.caption2).padding(8).background(Theme.cream.opacity(0.92), in: Capsule()).padding(12) }
                }
                HStack(alignment: .center, spacing: 16) { VStack(alignment: .leading, spacing: 9) { Text("You did it.").font(Theme.serif(43)).foregroundStyle(Theme.plum); Text(attempt.recipe.title).font(Theme.serif(25)).foregroundStyle(Theme.plum) }; Spacer(minLength: 0); ChefMascot(size: 66) }
                Label("Saved to your cooking story", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Theme.plum)
                Text("A little more confidence. A delicious thing you made.").font(.subheadline).foregroundStyle(Theme.muted)
                if !attempt.changes.isEmpty { VStack(alignment: .leading, spacing: 8) { SectionEyebrow(title: "Made your way"); ForEach(attempt.changes, id: \.self) { Text($0).font(.subheadline) } } }
                DisclosureGroup(isExpanded: $expanded) {
                    MemoryEditor(store: store, attemptID: attempt.id) { saved = true }.padding(.top, 20)
                } label: { Label("Add a photo, note, or rating", systemImage: "square.and.pencil").font(.subheadline.weight(.medium)) }
                if saved { Text("Your memory is saved.").font(.caption).foregroundStyle(Theme.plum).accessibilityIdentifier("memory-saved") }
                Button("Back to my cookbook") { store.tab = .cookbook; store.showCooking = false }.buttonStyle(FilledButton()).padding(.top, 8)
            }.padding(24)
        }.background(Theme.cream).onAppear { store.stopVoice() }
            .task(id: attempt.photoFile ?? attempt.photoPath) { image = await store.loadPhoto(attempt) }
    }
}

struct AttemptTile: View {
    let store: CompanionStore
    let attempt: CookAttempt
    @State private var image: UIImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else { ZStack { Theme.blush.opacity(0.5); Image(systemName: "fork.knife").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Theme.plum.opacity(0.6)) } }
                }.frame(height: 170).clipped().clipShape(RoundedRectangle(cornerRadius: 15))
                if image == nil { Text("Made by you").font(.caption2).foregroundStyle(Theme.plum).padding(12) }
            }
            Text(attempt.recipe.title).font(Theme.serif(22)).foregroundStyle(Theme.plum).lineLimit(2).multilineTextAlignment(.leading)
            Text(Date(timeIntervalSince1970: (attempt.finishedAt ?? 0) / 1000), style: .date).font(.caption).foregroundStyle(Theme.muted)
            if attempt.rating > 0 { Text(String(repeating: "★", count: min(5, attempt.rating))).font(.caption).foregroundStyle(Theme.berry).accessibilityLabel("Rated \(attempt.rating) out of 5") }
            if !attempt.notes.isEmpty { Text(attempt.notes).font(.caption).foregroundStyle(Theme.muted).lineLimit(2).multilineTextAlignment(.leading) }
        }.frame(maxWidth: .infinity, alignment: .leading).task(id: attempt.photoFile ?? attempt.photoPath) { image = await store.loadPhoto(attempt) }
    }
}

struct AttemptDetailView: View {
    @Bindable var store: CompanionStore
    let attemptID: String
    @Environment(\.dismiss) private var dismiss
    private var attempt: CookAttempt? { store.archive.attempts.first { $0.id == attemptID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let attempt {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(attempt.recipe.title).font(Theme.serif(34)).foregroundStyle(Theme.plum)
                        Text(Date(timeIntervalSince1970: (attempt.finishedAt ?? attempt.startedAt) / 1000), style: .date).font(.subheadline).foregroundStyle(Theme.muted)
                        if let end = attempt.finishedAt { Label("\(max(1, Int((end - (attempt.cookingStartedAt ?? attempt.startedAt)) / 60000))) minutes in your kitchen", systemImage: "clock").font(.caption).foregroundStyle(Theme.muted) }
                        MemoryEditor(store: store, attemptID: attemptID) { dismiss() }
                        if !attempt.changes.isEmpty { VStack(alignment: .leading, spacing: 10) { Text("Your changes").font(Theme.serif(24)).foregroundStyle(Theme.plum); ForEach(attempt.changes, id: \.self) { Text($0).font(.subheadline) } } }
                        DisclosureGroup("Cooking timeline") { ForEach(attempt.events) { event in HStack(alignment: .top, spacing: 14) { Text(Date(timeIntervalSince1970: event.at / 1000), style: .time).font(.caption).foregroundStyle(Theme.muted); Text(event.kind.replacingOccurrences(of: "_", with: " ") + (event.detail.isEmpty ? "" : ": " + event.detail)).font(.caption) }.padding(.vertical, 7) } }.font(.subheadline)
                        if !attempt.messages.isEmpty { DisclosureGroup("Chef advice from this cook") { ForEach(attempt.messages) { message in VStack(alignment: .leading, spacing: 7) { SectionEyebrow(title: message.role == "user" ? "You" : "Your chef"); Text(message.text).font(.subheadline) }.padding(.vertical, 8) } }.font(.subheadline) }
                        Button("Cook this again →") {
                            let recipe = store.recipes.first { $0.id == attempt.recipe.id } ?? attempt.recipe
                            let uid = store.uid; dismiss()
                            Task { try? await Task.sleep(for: .milliseconds(350)); guard store.uid == uid else { return }; store.selectedRecipe = recipe }
                        }.font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52)
                    }.padding(24)
                }
            }.background(Theme.cream).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct MemoryEditor: View {
    @Bindable var store: CompanionStore
    let attemptID: String
    let onSaved: () -> Void
    @State private var note = ""
    @State private var rating = 0
    @State private var photo = false
    @State private var image: UIImage?
    @State private var loaded = false
    private var attempt: CookAttempt? { store.archive.attempts.first { $0.id == attemptID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280).clipShape(RoundedRectangle(cornerRadius: 18)) }
            HStack { Button { photo = true } label: { Label(image == nil ? "Add a dish photo" : "Replace photo", systemImage: "camera").font(.subheadline).frame(minHeight: 44) }; Spacer(); if image != nil { Button("Remove", role: .destructive) { if store.removePhoto(attemptID) { image = nil } }.font(.caption).frame(minHeight: 44) } }
            VStack(alignment: .leading, spacing: 9) {
                Text("How did it turn out?").font(.subheadline.weight(.medium))
                HStack(spacing: 8) { ForEach(1...5, id: \.self) { value in Button { rating = rating == value ? 0 : value } label: { Image(systemName: value <= rating ? "star.fill" : "star").font(.title2).foregroundStyle(Theme.plum).frame(width: 44, height: 44) }.accessibilityLabel("Rate \(value) stars").accessibilityAddTraits(value == rating ? .isSelected : []) } }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("A note for next time").font(.subheadline.weight(.medium))
                TextField("What worked? What would you change?", text: $note, axis: .vertical).lineLimit(3...8).font(.body).padding(16).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("cooking-note").onChange(of: note) { _, value in note = String(value.prefix(3000)) }
            }
            Button("Save memory") { dismissCookingKeyboard(); if store.updateAttempt(attemptID, edit: { $0.notes = note; $0.rating = rating }) { onSaved() } }.buttonStyle(FilledButton())
        }.onAppear { guard !loaded else { return }; note = attempt?.notes ?? ""; rating = attempt?.rating ?? 0; loaded = true }.keyboardDone()
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
            Text("Made by you.").font(Theme.serif(37)).foregroundStyle(Theme.plum)
            Text("A little memory of something delicious.").font(.subheadline).foregroundStyle(Theme.muted)
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 330).clipShape(RoundedRectangle(cornerRadius: 22)) }
            else { Image(systemName: "camera").font(.system(size: 65, weight: .ultraLight)).foregroundStyle(Theme.plum).frame(height: 150) }
            Button("Take a photo") { Task { if await AVCaptureDevice.requestAccess(for: .video), UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.error = "Camera unavailable. Choose a photo or enable camera access in Settings." } } }.buttonStyle(FilledButton())
            PhotosPicker(selection: $selection, matching: .images) { Label("Choose from Photos", systemImage: "photo") }.frame(minHeight: 44)
            if let image { Button("Save dish photo") { if store.attachPhoto(image, attemptID: attemptID) { dismiss() } }.buttonStyle(FilledButton()) }
            Button("Skip for now") { dismiss() }.frame(minHeight: 44)
        }.padding(24) }.background(Theme.cream).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } } }
        .fullScreenCover(isPresented: $camera) { CompanionCamera { image = $0; camera = false } }
        .onChange(of: selection) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { image = UIImage(data: data) } } }
    }
}
