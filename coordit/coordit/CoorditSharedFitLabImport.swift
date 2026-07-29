import Foundation

#if os(iOS)
enum CoorditSharedFitLabImport {
    static let appGroupIdentifier = "group.com.inseong.coordit"
    static let didRequestOpenNotification = Notification.Name("CoorditSharedFitLabImportDidRequestOpen")

    private static let pendingURLKey = "coordit.pendingFitLabShareURL"
    private static let sourceApplicationKey = "coordit.pendingFitLabShareSource"

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

        defaults.set(productURL.absoluteString, forKey: pendingURLKey)
        defaults.set(sourceApplication, forKey: sourceApplicationKey)
        return defaults.synchronize()
    }

    static func consumePendingProductURL() -> URL? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let rawValue = defaults.string(forKey: pendingURLKey),
              let url = URL(string: rawValue),
              url.isHTTPOrHTTPSProductURL
        else { return nil }

        defaults.removeObject(forKey: pendingURLKey)
        defaults.removeObject(forKey: sourceApplicationKey)
        defaults.synchronize()
        return url
    }

    static func clearPendingProductURL() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.removeObject(forKey: pendingURLKey)
        defaults.removeObject(forKey: sourceApplicationKey)
        defaults.synchronize()
    }

    static func postOpenRequest(productURL: URL? = nil) {
        NotificationCenter.default.post(name: didRequestOpenNotification, object: productURL)
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
