import SwiftUI
import AuthenticationServices
import PhotosUI
import AVFoundation
import SafariServices
import FirebaseStorage
import FirebaseAuth
import GoogleSignIn
import ImageIO

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
    private var welcomePreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--companion-welcome")
        #else
        false
        #endif
    }
    var body: some View {
        Group {
            if welcomePreview || (account.accountID == nil && !preview) { CompanionWelcome() }
            else if store.loading { ZStack { Theme.cream.ignoresSafeArea(); ProgressView("Opening your kitchen…") } }
            else if !store.profile.onboardingComplete || store.profile.needsPreferenceReview { CompanionPreferences(store: store, onboarding: true) }
            else { CompanionHome(store: store) }
        }
        .id(account.accountID ?? "signed-out").tint(Theme.plum).preferredColorScheme(.light)
        .task { store.switchAccount(account.accountID); account.onDeleteLocalAccount = { uid in try await store.deleteAccountData(uid) } }
        .onChange(of: account.accountID) { _, id in store.switchAccount(id) }
        .onChange(of: phase) { _, phase in
            if phase == .active { store.foreground = true; store.consumeSharedLinks(); store.consumeRecipeShare(); store.sync() }
            else if phase == .background { store.background() }
            keepAwake()
        }
        .onChange(of: store.showCooking) { _, cooking in keepAwake(); if !cooking { store.consumeRecipeShare() } }
        .onOpenURL { url in
            if !store.openRecipeShare(url), !Auth.auth().canHandle(url) { _ = GIDSignIn.sharedInstance.handle(url) }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { _ = store.openRecipeShare(url) }
        }
        .onChange(of: store.profile.keepAwake) { _, _ in keepAwake() }
        .onChange(of: store.active?.finishedAt) { _, _ in keepAwake() }
        .alert("A little attention needed", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private func keepAwake() { UIApplication.shared.isIdleTimerDisabled = phase == .active && store.showCooking && store.active?.finishedAt == nil && store.profile.keepAwake }
}

@MainActor struct RecipePhoto: View {
    let recipe: CompanionRecipe
    @State private var downloaded: UIImage?
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private var imageKey: String { "\(Auth.auth().currentUser?.uid ?? "")|\(recipe.id)|\(recipe.imagePath ?? "")|\(recipe.youtubeThumbnailURL?.absoluteString ?? "")" }
    var body: some View {
        GeometryReader { geometry in
            Group {
                if recipe.id == "preview-pasta" { Image("WelcomeFood").resizable().scaledToFill() }
                else if let downloaded { Image(uiImage: downloaded).resizable().scaledToFill().accessibilityIdentifier("recipe-photo-loaded") }
                else { placeholder }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityLabel(recipe.title).task(id: imageKey) {
            let key = imageKey as NSString
            downloaded = Self.images.object(forKey: key)
            guard downloaded == nil, recipe.id != "preview-pasta" else { return }
            // Public YouTube thumbnails do not need a Firebase download or its retries.
            if let url = recipe.youtubeThumbnailURL {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000,
                   let image = Self.thumbnail(data), !Task.isCancelled {
                    Self.images.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height) * 4)
                    downloaded = image; return
                }
            }
            guard !Task.isCancelled, let uid = Auth.auth().currentUser?.uid, let path = recipe.imagePath,
                  path.hasPrefix("users/\(uid)/recipeMedia/\(recipe.id)/cover-") else { return }
            if let data = try? await Storage.storage().reference().child(path).data(maxSize: 2_000_000),
               Auth.auth().currentUser?.uid == uid, !Task.isCancelled, let image = Self.thumbnail(data) {
                Self.images.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height) * 4)
                downloaded = image
            }
        }
    }
    private static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 960, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    private var placeholder: some View {
        ZStack { Theme.blush; Image(systemName: "fork.knife").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Theme.plum.opacity(0.6)) }
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
struct SourceVideoView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
func ingredientSymbol(_ name: String) -> String {
    let lower = name.lowercased()
    if lower.contains("oil") || lower.contains("water") { return "drop" }
    if lower.contains("milk") || lower.contains("cream") { return "mug" }
    if lower.contains("chicken") || lower.contains("meat") { return "fork.knife" }
    if lower.contains("fish") || lower.contains("salmon") { return "fish" }
    if lower.contains("flour") || lower.contains("pasta") || lower.contains("rice") { return "takeoutbag.and.cup.and.straw" }
    return "leaf"
}
