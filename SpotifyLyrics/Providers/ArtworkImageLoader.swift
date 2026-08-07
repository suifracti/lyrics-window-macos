import AppKit
import Foundation

@MainActor
public final class ArtworkImageLoader {
    public static let shared = ArtworkImageLoader()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlightTasks: [URL: Task<NSImage?, Never>] = [:]

    private let session: URLSession

    private init() {
        cache.countLimit = 128
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .useProtocolCachePolicy
        let urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: "spotify_lyrics_artwork_cache"
        )
        config.urlCache = urlCache
        self.session = URLSession(configuration: config)
    }

    public func image(for url: URL?) async -> NSImage? {
        guard let url else { return nil }
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }

        if let existingTask = inFlightTasks[url] {
            return await existingTask.value
        }

        let task = Task<NSImage?, Never>.detached { [session, cache] in
            do {
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let image = NSImage(data: data) else {
                    return nil
                }
                await MainActor.run {
                    cache.setObject(image, forKey: key)
                }
                return image
            } catch {
                return nil
            }
        }

        inFlightTasks[url] = task
        let image = await task.value
        inFlightTasks.removeValue(forKey: url)
        return image
    }
}
