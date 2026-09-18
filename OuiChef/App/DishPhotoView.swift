import SwiftUI
import PhotosUI
import AVFoundation

struct DishPhotoView: View {
    let store: ChefStore
    let attemptID: UUID
    let accountID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var photo: UIImage?
    @State private var camera = false
    @State private var selection: PhotosPickerItem?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text("Made by you.").font(Theme.serif(35))
                    Text("Save a little memory of what you cooked.").foregroundStyle(.secondary)
                    if let photo { Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 350).clipShape(RoundedRectangle(cornerRadius: 18)) }
                    else { Image(systemName: "camera").font(.system(size: 70, weight: .ultraLight)).frame(height: 180).foregroundStyle(Theme.green) }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(photo == nil ? "Take photo" : "Retake photo") {
                            Task {
                                if await AVCaptureDevice.requestAccess(for: .video) { camera = true }
                                else { notice = "Camera access is off. You can choose a photo, add one later, or enable the camera in Settings." }
                            }
                        }.buttonStyle(FilledButton())
                    }
                    PhotosPicker(selection: $selection, matching: .images) { Label("Choose a photo", systemImage: "photo") }.frame(minHeight: 44)
                    if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if photo != nil {
                        Button("Save dish photo") {
                            guard store.accountID == accountID, store.photoAttemptID == attemptID, let photo else { dismiss(); return }
                            guard let data = Self.compressed(photo) else { notice = "This image could not be saved. Please try another photo."; return }
                            if store.attachPhoto(data, to: attemptID) { dismiss() }
                        }.buttonStyle(FilledButton())
                    }
                    Button("Skip for now") { dismiss() }.frame(minHeight: 44)
                }.padding(24)
            }.background(Theme.cream)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .fullScreenCover(isPresented: $camera) { DishCamera { image in if let image { photo = image }; camera = false } }
        .onChange(of: selection) { _, item in
            Task {
                do {
                    guard let data = try await item?.loadTransferable(type: Data.self), store.accountID == accountID else { return }
                    photo = UIImage(data: data)
                } catch { notice = "The photo could not load. Please try again." }
            }
        }
    }

    static func compressed(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        // Drawing into a fresh JPEG normalizes orientation and drops source/location metadata.
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.75), data.count <= 2_000_000 else { return nil }
        return data
    }
}

private struct DishCamera: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finish: (UIImage?) -> Void
        init(_ finish: @escaping (UIImage?) -> Void) { self.finish = finish }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { finish(info[.originalImage] as? UIImage) }
    }
}
