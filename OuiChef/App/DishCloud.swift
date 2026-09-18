import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
final class DishCloud {
    private let db = Firestore.firestore()
    private var files: StorageReference { Storage.storage().reference() }

    init() {
        // Local persistence owns retries; avoid holding account changes behind ten-minute uploads.
        Storage.storage().maxUploadRetryTime = 20
        Storage.storage().maxDownloadRetryTime = 15
        Storage.storage().maxOperationRetryTime = 15
    }

    private func authorize(_ uid: String) throws {
        guard Auth.auth().currentUser?.uid == uid, !Task.isCancelled else { throw CancellationError() }
    }
    func path(_ uid: String, _ id: UUID) -> String { "users/\(uid)/completedRecipes/\(id.uuidString)/dish.jpg" }
    func page(_ uid: String, after: DocumentSnapshot?) async throws -> ([CompletedDish], DocumentSnapshot?) {
        try authorize(uid)
        var query = db.collection("users/\(uid)/completedRecipes").order(by: "completedAt", descending: true).limit(to: 12)
        if let after { query = query.start(afterDocument: after) }
        let docs = try await query.getDocuments(source: .server).documents
        try authorize(uid)
        return (try docs.map { try $0.data(as: CompletedDish.self) }, docs.count == 12 ? docs.last : nil)
    }
    func save(_ dish: CompletedDish, uid: String, image: Data?) async throws -> String? {
        try authorize(uid)
        var photoPath = dish.photoPath
        if let image {
            guard image.count <= 2_000_000 else { throw CookingError.invalid("The photo is too large.") }
            let metadata = StorageMetadata(); metadata.contentType = "image/jpeg"
            let destination = path(uid, dish.id)
            _ = try await files.child(destination).putDataAsync(image, metadata: metadata)
            photoPath = destination
        } else if dish.deletePhoto == true {
            try await deletePhoto(uid, id: dish.id); photoPath = nil
        }
        try authorize(uid)
        var data: [String: Any] = ["id": dish.id.uuidString, "recipeID": dish.recipeID,
            "recipeVersion": dish.recipeVersion, "title": dish.title, "chefName": dish.chefName,
            "servings": dish.servings, "completedAt": Timestamp(date: dish.completedAt), "adjustments": dish.adjustments]
        if let photoPath { data["photoPath"] = photoPath }
        if let version = dish.photoVersion, photoPath != nil { data["photoVersion"] = version }
        try await db.document("users/\(uid)/completedRecipes/\(dish.id.uuidString)").setData(data)
        try authorize(uid)
        return photoPath
    }
    func image(_ dish: CompletedDish, uid: String) async throws -> Data? {
        try authorize(uid)
        guard let photo = dish.photoPath, photo == path(uid, dish.id) else { return nil }
        let data = try await files.child(photo).data(maxSize: 2_000_000)
        try authorize(uid)
        return data
    }
    private func deletePhoto(_ uid: String, id: UUID) async throws {
        try authorize(uid)
        do { try await files.child(path(uid, id)).delete() }
        catch where (error as NSError).code == StorageErrorCode.objectNotFound.rawValue { }
    }
    func delete(_ id: UUID, uid: String) async throws {
        try await deletePhoto(uid, id: id)
        try authorize(uid)
        try await db.document("users/\(uid)/completedRecipes/\(id.uuidString)").delete()
    }
    func deleteAll(_ uid: String) async throws {
        // Also remove uploaded photos whose metadata write was interrupted.
        try authorize(uid)
        var token: String?
        repeat {
            let root = files.child("users/\(uid)/completedRecipes")
            let page: StorageListResult
            if let token { page = try await root.list(maxResults: 100, pageToken: token) }
            else { page = try await root.list(maxResults: 100) }
            for prefix in page.prefixes {
                if let id = UUID(uuidString: prefix.name) { try await deletePhoto(uid, id: id) }
            }
            token = page.pageToken
        } while token != nil
        while true {
            try authorize(uid)
            let docs = try await db.collection("users/\(uid)/completedRecipes").limit(to: 100).getDocuments()
            if docs.isEmpty { break }
            let batch = db.batch(); for doc in docs.documents { batch.deleteDocument(doc.reference) }
            try await batch.commit()
        }
    }
}
