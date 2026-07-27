import AppKit
import Foundation

@MainActor
public final class ArtworkImageLoader {
    public static let shared = ArtworkImageLoader()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 64
    }

    public func image(for url: URL?) async -> NSImage? {
        guard let url else { return nil }
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = NSImage(data: data) else {
                return nil
            }
            cache.setObject(image, forKey: key)
            return image
        } catch {
            return nil
        }
    }
}
