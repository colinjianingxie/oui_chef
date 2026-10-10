import UIKit

enum DishPhoto {
    static func compressed(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        // A fresh JPEG normalizes orientation and removes source/location metadata.
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size)); image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.75), data.count <= 2_000_000 else { return nil }
        return data
    }
}
