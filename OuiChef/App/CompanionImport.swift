import SwiftUI

struct ImportRecipePreview: View {
    let item: RecipeImport
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = item.youtubeThumbnailURL {
                GeometryReader { geometry in
                    AsyncImage(url: url) { image in image.resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                    placeholder: { ZStack { Theme.blush.opacity(0.6); if item.running { ProgressView() } } }
                }.frame(height: compact ? 155 : 200).clipShape(RoundedRectangle(cornerRadius: 17)).accessibilityLabel("Recipe thumbnail")
            } else if compact {
                RoundedRectangle(cornerRadius: 17).fill(Theme.blush.opacity(0.6)).frame(height: 155)
                    .overlay { if item.running { ProgressView() } else { Image(systemName: "info.circle").foregroundStyle(Theme.plum) } }
                    .accessibilityHidden(true)
            }
            Text(item.previewTitle ?? "Your recipe").font(Theme.serif(compact ? 20 : 25)).lineLimit(compact ? 2 : nil)
                .redacted(reason: item.previewTitle == nil && item.running ? .placeholder : [])
            if let creator = item.previewCreator { Text(creator).font(.caption).foregroundStyle(.secondary) }
            if compact {
                Text(item.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            } else {
                if let summary = item.previewSummary { Text(summary).font(.subheadline).foregroundStyle(.secondary) }
                if item.previewIngredients != nil { previewSection("Ingredients", lines: item.previewIngredients) }
                if item.previewSteps != nil { previewSection("Cooking steps", lines: item.previewSteps) }
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
                        if item.status == "ready" {
                            Text("Your recipe is ready.").font(Theme.serif(37))
                            if let recipe = store.recipes.first(where: { $0.id == item.recipeID }) {
                                RecipePhoto(recipe: recipe).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20))
                                Text(recipe.title).font(Theme.serif(28))
                                if !recipe.warnings.isEmpty {
                                    VStack(alignment: .leading, spacing: 9) {
                                        Label("Before you cook", systemImage: "exclamationmark.circle").font(.headline)
                                        ForEach(recipe.warnings, id: \.self) { Text($0).font(.subheadline) }
                                    }.padding(18).background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                                }
                                Button("Review recipe") {
                                    let accountID = store.uid
                                    dismiss()
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(350))
                                        guard store.uid == accountID else { return }
                                        store.selectedRecipe = recipe
                                    }
                                }.buttonStyle(FilledButton()).accessibilityIdentifier("review-imported-recipe")
                                Text("Saved to your cookbook.").font(.caption).foregroundStyle(.secondary)
                            } else { ProgressView("Opening your recipe…") }
                        } else {
                            ChefMascot(size: 64)
                            Text(item.running ? "Your recipe is\ncoming together." : "Let’s try that again.").font(Theme.serif(37)).foregroundStyle(Theme.plum)
                            importRow(item)
                            ImportRecipePreview(item: item)
                        }
                        if !item.running { Button("Import another recipe") { store.focusedImportID = nil; url = ""; recipeText = "" }.font(.subheadline) }
                    } else {
                        Image(systemName: "link").font(.system(size: 26)).foregroundStyle(Theme.plum).frame(width: 62, height: 62).background(Theme.blush, in: Circle())
                        Text("Turn a recipe\ninto your recipe.").font(Theme.serif(37)).foregroundStyle(Theme.plum)
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
                        HStack { Rectangle().frame(height: 1); Text("or").font(.caption); Rectangle().frame(height: 1) }.foregroundStyle(Theme.plum.opacity(0.3))
                        VStack(spacing: 12) {
                            Button { dismissCookingKeyboard(); textMode.toggle() } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: textMode ? "link" : "doc.text").frame(width: 24)
                                    Text(textMode ? "Paste a link" : "Paste the text")
                                    Spacer(); Image(systemName: "chevron.right").font(.caption)
                                }.padding(18).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain).accessibilityIdentifier("toggle-import-mode").disabled(store.importing)
                        }
                        Label("Or tap Share in another app, then choose Oui Chef.", systemImage: "square.and.arrow.up").font(.caption).foregroundStyle(Theme.muted).lineSpacing(4)
                        ChefCallout(text: "Good recipes deserve to be cooked.")
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
            HStack { Text(item.source).font(.headline); Spacer(); if item.running { ProgressView() } else { Image(systemName: item.status == "ready" ? "checkmark.circle.fill" : "info.circle").foregroundStyle(Theme.plum) } }
            Text(item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if item.running {
                ForEach(Array(RecipeImport.stages.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 12) {
                        if index < item.progressStage { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.plum) }
                        else if index == item.progressStage { ProgressView().controlSize(.small) }
                        else { Image(systemName: "circle").foregroundStyle(Theme.plum.opacity(0.25)) }
                        Text(label).font(.subheadline).foregroundStyle(index <= item.progressStage ? Theme.ink : .secondary)
                    }.accessibilityElement(children: .combine)
                        .accessibilityLabel("\(label): \(index < item.progressStage ? "Complete" : index == item.progressStage ? "In progress" : "Waiting")")
                }
            }
            Text(item.message).font(.subheadline).foregroundStyle(.secondary)
            if item.running {
                HStack { Text("You can leave. We’ll keep working.").font(.caption); Spacer(); Button("Cancel") { Task { await store.cancelImport(item.id) } }.font(.caption) }
            } else if ["failed","skipped","canceled"].contains(item.status) {
                Button("Try again or paste recipe text") { url = item.url; textMode = item.url.isEmpty; store.focusedImportID = nil }.font(.subheadline)
            }
        }.padding(19).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
    }
}
