import Foundation

#if os(iOS)
enum CoorditSharedFitLabImport {
    static let appGroupIdentifier = "group.com.inseong.coordit"
    static let didRequestOpenNotification = Notification.Name("CoorditSharedFitLabImportDidRequestOpen")

    private static let pendingURLKey = "coordit.pendingFitLabShareURL"
    private static let sourceApplicationKey = "coordit.pendingFitLabShareSource"
    private static let pendingQueueKey = "coordit.pendingFitLabShareQueue.v1"

    private struct PendingImport: Codable, Equatable {
        let url: String
        let sourceApplication: String?
    }

    static var openURL: URL {
        URL(string: "coordit://fitlab/shared")!
    }

    static func isOpenURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "coordit"
            && url.host(percentEncoded: false)?.lowercased() == "fitlab"
            && url.path == "/shared"
    }

    static func openURL(for productURL: URL) -> URL {
        var components = URLComponents(url: openURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "url", value: productURL.absoluteString)]
        return components?.url ?? openURL
    }

    static func productURL(fromOpenURL url: URL) -> URL? {
        guard isOpenURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let productURL = URL(string: value),
              productURL.isHTTPOrHTTPSProductURL
        else { return nil }
        return productURL
    }

    @discardableResult
    static func store(productURL: URL, sourceApplication: String? = nil) -> Bool {
        guard productURL.isHTTPOrHTTPSProductURL,
              let defaults = UserDefaults(suiteName: appGroupIdentifier)
        else { return false }

        var pending = pendingImports(in: defaults)
        let entry = PendingImport(url: productURL.absoluteString, sourceApplication: sourceApplication)
        // A URL-scheme hand-off and the shared App Group can carry the same
        // product link. Store it once regardless of its originating app.
        guard !pending.contains(where: { $0.url == entry.url }) else { return true }
        pending.append(entry)
        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingQueueKey)
        defaults.set(productURL.absoluteString, forKey: pendingURLKey)
        defaults.set(sourceApplication, forKey: sourceApplicationKey)
        return defaults.synchronize()
    }

    static func consumePendingProductURL() -> URL? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              !pendingImports(in: defaults).isEmpty || defaults.string(forKey: pendingURLKey) != nil
        else { return nil }

        var pending = pendingImports(in: defaults)
        if pending.isEmpty,
           let legacy = defaults.string(forKey: pendingURLKey) {
            pending = [PendingImport(url: legacy, sourceApplication: defaults.string(forKey: sourceApplicationKey))]
        }
        guard let entry = pending.first,
              let url = URL(string: entry.url),
              url.isHTTPOrHTTPSProductURL
        else {
            defaults.removeObject(forKey: pendingQueueKey)
            return nil
        }
        pending.removeFirst()
        if pending.isEmpty {
            defaults.removeObject(forKey: pendingQueueKey)
            defaults.removeObject(forKey: pendingURLKey)
            defaults.removeObject(forKey: sourceApplicationKey)
        } else {
            defaults.set(try? JSONEncoder().encode(pending), forKey: pendingQueueKey)
            defaults.set(pending[0].url, forKey: pendingURLKey)
            defaults.set(pending[0].sourceApplication, forKey: sourceApplicationKey)
        }
        defaults.synchronize()
        return url
    }

    static func clearPendingProductURL() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.removeObject(forKey: pendingQueueKey)
        defaults.removeObject(forKey: pendingURLKey)
        defaults.removeObject(forKey: sourceApplicationKey)
        defaults.synchronize()
    }

    static func removePendingProductURL(matching productURL: URL) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        var pending = pendingImports(in: defaults)
        if pending.isEmpty,
           let legacy = defaults.string(forKey: pendingURLKey) {
            pending = [PendingImport(url: legacy, sourceApplication: defaults.string(forKey: sourceApplicationKey))]
        }

        pending.removeAll { $0.url == productURL.absoluteString }
        if pending.isEmpty {
            clearPendingProductURL()
            return
        }

        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingQueueKey)
        defaults.set(pending[0].url, forKey: pendingURLKey)
        defaults.set(pending[0].sourceApplication, forKey: sourceApplicationKey)
        defaults.synchronize()
    }

    static func postOpenRequest(productURL: URL? = nil) {
        NotificationCenter.default.post(name: didRequestOpenNotification, object: productURL)
    }

    private static func pendingImports(in defaults: UserDefaults) -> [PendingImport] {
        guard let data = defaults.data(forKey: pendingQueueKey),
              let imports = try? JSONDecoder().decode([PendingImport].self, from: data)
        else { return [] }
        return imports.filter { URL(string: $0.url)?.isHTTPOrHTTPSProductURL == true }
    }
}

extension URL {
    var isHTTPOrHTTPSProductURL: Bool {
        guard let scheme = scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              host(percentEncoded: false) != nil
        else { return false }
        return user == nil && password == nil
    }
}
#endif
