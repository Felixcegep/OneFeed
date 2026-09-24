import Foundation
import ImageIO

/// Decodes feed artwork at the size the row or hero actually draws.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [String: CGImage] = [:]
    private var order: [String] = []
    private let limit = 64
    private var inflight: [String: Load] = [:]

    private final class Load: @unchecked Sendable {
        let task: Task<CGImage?, Never>
        var users = 1
        init(task: Task<CGImage?, Never>) { self.task = task }
    }

    func image(for url: URL, maxPixel: Int) async -> CGImage? {
        let key = "\(maxPixel)|\(url.absoluteString)"
        if let cached = images[key] { return cached }
        let load: Load
        let started: Bool
        if let existing = inflight[key] {
            existing.users += 1
            load = existing
            started = false
        } else {
            let task = Task { await Self.load(url, maxPixel: maxPixel) }
            load = Load(task: task)
            inflight[key] = load
            started = true
        }
        let token = LeaveToken()
        let image = await withTaskCancellationHandler {
            await load.task.value
        } onCancel: {
            Task { await token.perform { await self.abandon(key, cancelWhenIdle: started) } }
        }
        await token.perform { await self.finish(key, image: image) }
        return image
    }

    private func finish(_ key: String, image: CGImage?) {
        release(key, cancelWhenIdle: false)
        if let image { store(image, for: key) }
    }

    private func abandon(_ key: String, cancelWhenIdle: Bool) {
        release(key, cancelWhenIdle: cancelWhenIdle)
    }

    private func release(_ key: String, cancelWhenIdle: Bool) {
        guard let load = inflight[key] else { return }
        load.users -= 1
        guard load.users <= 0 else { return }
        if cancelWhenIdle { load.task.cancel() }
        inflight[key] = nil
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

    private nonisolated static func load(_ url: URL, maxPixel: Int) async -> CGImage? {
        if Task.isCancelled { return nil }
        let data: Data?
        if url.isFileURL {
            data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: url)
            }.value
        } else {
            do {
                data = try await URLSession.shared.data(from: url).0
            } catch {
                return nil
            }
        }
        guard let data, !data.isEmpty, !Task.isCancelled else { return nil }
        return await Task.detached(priority: .utility) {
            downsample(data, maxPixel: maxPixel)
        }.value
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

/// Runs a leave action once, whether the load finishes or the row scrolls away.
private final class LeaveToken: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func perform(_ body: () async -> Void) async {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        await body()
    }
}
