import Foundation
import ImageIO

/// Decodes feed artwork at the size the row or hero actually draws.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [String: CGImage] = [:]
    private var order: [String] = []
    private let limit = 64

    func image(for url: URL, maxPixel: Int) async -> CGImage? {
        let key = "\(maxPixel)|\(url.absoluteString)"
        if let cached = images[key] {
            return cached
        }
        let data: Data
        if url.isFileURL {
            guard let file = try? Data(contentsOf: url) else { return nil }
            data = file
        } else {
            guard let loaded = try? await URLSession.shared.data(from: url).0 else { return nil }
            data = loaded
        }
        guard let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
        store(image, for: key)
        return image
    }

    private func store(_ image: CGImage, for key: String) {
        images[key] = image
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > limit {
            let oldest = order.removeFirst()
            images.removeValue(forKey: oldest)
        }
    }

    private nonisolated static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions)
    }
}
