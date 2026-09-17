import UIKit

/// Keeps AI Insights photo attachments small — fast to send, and well
/// under the relay's request-size limits.
enum ImageResizer {
    static func resizedJPEGData(from image: UIImage, maxDimension: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
        let size = image.size
        let longestSide = max(size.width, size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1.0
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
