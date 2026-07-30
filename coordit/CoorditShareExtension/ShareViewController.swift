import Foundation
import LinkPresentation
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let card = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    private let brandColor = UIColor(red: 0.02, green: 0.08, blue: 0.30, alpha: 1)
    private var productURL: URL?
    private var didResolveURL = false
    private var didAppear = false
    private var didFinalize = false
    private var didCompleteRequest = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadSharedURL()
    }

    // iOS blocks a Share Extension from launching its containing app, so the
    // reliable channel is the App Group: we save the link here, then confirm.
    // A best-effort open() still runs in case a future OS permits it.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
        finalizeIfReady()
    }

    private func configureView() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.18)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        view.addSubview(card)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = brandColor
        spinner.startAnimating()

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = brandColor
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        iconView.isHidden = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "무신사 링크 담는 중…"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = " "
        subtitleLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("닫기", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeButton.tintColor = .secondaryLabel
        closeButton.isHidden = true
        closeButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        [spinner, iconView, titleLabel, subtitleLabel, closeButton].forEach(card.addSubview)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            iconView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: spinner.centerYAnchor),
            iconView.heightAnchor.constraint(equalToConstant: 46),

            titleLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            closeButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            closeButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            closeButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
    }

    // MARK: - Load the shared URL

    private func loadSharedURL() {
        let extensionItems = extensionContext?.inputItems
            .compactMap({ $0 as? NSExtensionItem }) ?? []
        var resolvedURLs = extensionItems.flatMap(Self.urls(from:))

        let providers = extensionItems
            .flatMap({ $0.attachments ?? [] })
            .filter { !$0.registeredTypeIdentifiers.isEmpty }
        guard !providers.isEmpty else {
            handleLoadedURL(Self.preferredURL(in: resolvedURLs))
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()

        for provider in providers {
            for typeIdentifier in Self.preferredTypeIdentifiers(for: provider) {
                group.enter()
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                    let urls = Self.urls(from: item)
                    if !urls.isEmpty {
                        lock.lock()
                        resolvedURLs.append(contentsOf: urls)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.handleLoadedURL(Self.preferredURL(in: resolvedURLs))
        }
    }

    private func handleLoadedURL(_ url: URL?) {
        didResolveURL = true
        productURL = url
        finalizeIfReady()
    }

    // MARK: - Save the link, confirm, dismiss

    private func finalizeIfReady() {
        guard didAppear, didResolveURL, !didFinalize else { return }
        didFinalize = true

        guard let productURL else {
            showUnsupportedShare()
            return
        }

        // The App Group is the reliable hand-off: coordit reads this the next
        // time it opens and drops the link straight into Fit Lab.
        guard CoorditShareImportBridge.store(productURL: productURL) else {
            showStorageFailure()
            return
        }

        // Best-effort launch in case the OS allows it (most don't for Share
        // extensions); the confirmation below is what the user actually relies on.
        let openURL = CoorditShareImportBridge.openURL(for: productURL)
        extensionContext?.open(openURL, completionHandler: nil)

        showSaved(host: productURL.host(percentEncoded: false))
        completeRequest(after: 1.15)
    }

    private func showSaved(host: String?) {
        spinner.stopAnimating()
        spinner.isHidden = true
        iconView.image = UIImage(systemName: "checkmark.circle.fill")
        iconView.tintColor = UIColor.systemGreen
        iconView.isHidden = false
        titleLabel.text = "Fit Lab에 담았어요"
        subtitleLabel.text = "coordit을 열면 링크가 자동으로 들어가 있어요."
    }

    private func showUnsupportedShare() {
        spinner.stopAnimating()
        spinner.isHidden = true
        iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        iconView.tintColor = UIColor.systemOrange
        iconView.isHidden = false
        titleLabel.text = "상품 링크를 찾지 못했어요"
        subtitleLabel.text = "무신사 상품 페이지의 공유에서 다시 시도해 주세요."
        closeButton.isHidden = false
    }

    private func showStorageFailure() {
        spinner.stopAnimating()
        spinner.isHidden = true
        iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        iconView.tintColor = UIColor.systemRed
        iconView.isHidden = false
        titleLabel.text = "링크를 저장하지 못했어요"
        subtitleLabel.text = "coordit을 다시 열어 확인한 뒤, 공유를 한 번 더 시도해 주세요."
        closeButton.isHidden = false
    }

    private func completeRequest(after delay: TimeInterval) {
        guard !didCompleteRequest else { return }
        didCompleteRequest = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.inseong.coordit.share",
            code: NSUserCancelledError
        ))
    }

    // MARK: - URL extraction

    private static func preferredTypeIdentifiers(for provider: NSItemProvider) -> [String] {
        let preferred = [
            "com.apple.linkmetadata",
            UTType.url.identifier,
            UTType.text.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
            UTType.data.identifier
        ]
        let registered = provider.registeredTypeIdentifiers
        let preferredMatches = preferred.filter { identifier in
            provider.hasItemConformingToTypeIdentifier(identifier)
        }
        let remaining = registered.filter { !preferredMatches.contains($0) }
        return preferredMatches + remaining
    }

    private static func urls(from item: NSSecureCoding?) -> [URL] {
        if let url = item as? URL, url.isHTTPOrHTTPSProductURL {
            return [url]
        }

        if let metadata = item as? LPLinkMetadata {
            return [metadata.originalURL, metadata.url]
                .compactMap { $0 }
                .filter(\.isHTTPOrHTTPSProductURL)
        }

        if let value = item as? String {
            return urls(in: value)
        }

        if let value = item as? NSString {
            return urls(in: String(value))
        }

        if let data = item as? Data,
           let value = String(data: data, encoding: .utf8) {
            return urls(in: value)
        }

        return []
    }

    private static func urls(from extensionItem: NSExtensionItem) -> [URL] {
        let textCandidates = [
            extensionItem.attributedTitle?.string,
            extensionItem.attributedContentText?.string
        ]

        return textCandidates
            .compactMap { $0 }
            .flatMap(urls(in:))
            + urls(in: String(describing: extensionItem.userInfo ?? [:]))
    }

    private static func preferredURL(in urls: [URL]) -> URL? {
        let uniqueURLs = urls.reduce(into: [URL]()) { result, url in
            guard !result.contains(url) else { return }
            result.append(url)
        }
        return uniqueURLs.first(where: \.isMusinsaProductURL)
            ?? uniqueURLs.first(where: { !$0.isMusinsaOneLinkURL })
            ?? uniqueURLs.first
    }

    private static func urls(in value: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return detector?
            .matches(in: value, options: [], range: range)
            .compactMap(\.url)
            .filter(\.isHTTPOrHTTPSProductURL) ?? []
    }
}

private enum CoorditShareImportBridge {
    static let appGroupIdentifier = "group.com.inseong.coordit"
    static let openURL = URL(string: "coordit://fitlab/shared")!
    private static let pendingURLKey = "coordit.pendingFitLabShareURL"
    private static let sourceApplicationKey = "coordit.pendingFitLabShareSource"
    private static let pendingQueueKey = "coordit.pendingFitLabShareQueue.v1"

    private struct PendingImport: Codable, Equatable {
        let url: String
        let sourceApplication: String?
    }

    @discardableResult
    static func store(productURL: URL) -> Bool {
        guard productURL.isHTTPOrHTTPSProductURL,
              let defaults = UserDefaults(suiteName: appGroupIdentifier)
        else { return false }

        var pending = pendingImports(in: defaults)
        let entry = PendingImport(url: productURL.absoluteString, sourceApplication: "share-extension")
        guard !pending.contains(where: { $0.url == entry.url }) else { return true }
        pending.append(entry)
        defaults.set(try? JSONEncoder().encode(pending), forKey: pendingQueueKey)
        defaults.set(productURL.absoluteString, forKey: pendingURLKey)
        defaults.set("share-extension", forKey: sourceApplicationKey)
        return defaults.synchronize()
    }

    static func openURL(for productURL: URL) -> URL {
        var components = URLComponents(url: openURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "url", value: productURL.absoluteString)]
        return components?.url ?? openURL
    }

    private static func pendingImports(in defaults: UserDefaults) -> [PendingImport] {
        guard let data = defaults.data(forKey: pendingQueueKey),
              let imports = try? JSONDecoder().decode([PendingImport].self, from: data)
        else { return [] }
        return imports.filter { URL(string: $0.url)?.isHTTPOrHTTPSProductURL == true }
    }
}

private extension URL {
    var isHTTPOrHTTPSProductURL: Bool {
        guard let scheme = scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              host(percentEncoded: false) != nil
        else { return false }
        return user == nil && password == nil
    }

    var isMusinsaProductURL: Bool {
        guard let host = host(percentEncoded: false)?.lowercased() else { return false }
        return (host == "musinsa.com" || host.hasSuffix(".musinsa.com"))
            && path.contains("/products/")
    }

    var isMusinsaOneLinkURL: Bool {
        host(percentEncoded: false)?.lowercased().contains("musinsa.onelink.me") == true
    }
}
