import Foundation
import Combine
import StoreKit

#if os(iOS)
enum CoorditThreadProductID: String, CaseIterable, Sendable {
    case pack5 = "com.inseong.coordit.thread.5"
    case pack10 = "com.inseong.coordit.thread.10"
    case pack20 = "com.inseong.coordit.thread.20"

    var threadAmount: Int {
        switch self {
        case .pack5: 5
        case .pack10: 10
        case .pack20: 20
        }
    }

    var accessibilityIdentifier: String {
        "coordit-thread-charge-pack-\(threadAmount)"
    }
}

struct CoorditThreadProduct: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
    let threadAmount: Int

    var accessibilityIdentifier: String {
        CoorditThreadProductID(rawValue: id)?.accessibilityIdentifier
            ?? "coordit-thread-charge-pack-unknown"
    }
}

struct CoorditThreadStoreTransaction: @unchecked Sendable {
    let id: String
    let diagnosticLabel: String
    let productID: String
    let appAccountToken: UUID?
    let jwsRepresentation: String
    let finish: @Sendable () async -> Void
}

enum CoorditThreadStorePurchaseResult: @unchecked Sendable {
    case verified(CoorditThreadStoreTransaction)
    case userCancelled
    case pending
    case unverified
}

@MainActor
protocol CoorditThreadStorefront: AnyObject {
    func loadProducts() async throws -> [CoorditThreadProduct]
    func purchase(productID: String, appAccountToken: UUID) async throws -> CoorditThreadStorePurchaseResult
    func unfinishedTransactions() async -> [CoorditThreadStorePurchaseResult]
    func transactionUpdates() -> AsyncStream<CoorditThreadStorePurchaseResult>
}

#if DEBUG
@MainActor
private protocol CoorditThreadPurchaseFixtureReporting: AnyObject {
    func bindFixtureEventSink(
        _ sink: @escaping @MainActor @Sendable (String) -> Void
    )
}
#endif

@MainActor
final class CoorditStoreKitThreadStorefront: CoorditThreadStorefront {
    private var productsByID: [String: Product] = [:]

    func loadProducts() async throws -> [CoorditThreadProduct] {
        let requestedIDs = CoorditThreadProductID.allCases.map(\.rawValue)
        let fetched = try await Product.products(for: requestedIDs)
        let consumables = fetched.filter {
            CoorditThreadProductID(rawValue: $0.id) != nil && $0.type == .consumable
        }
        guard Set(consumables.map(\.id)) == Set(requestedIDs) else {
            throw CoorditThreadPurchaseError.productsUnavailable
        }
        productsByID = Dictionary(uniqueKeysWithValues: consumables.map { ($0.id, $0) })
        return consumables
            .compactMap { product -> CoorditThreadProduct? in
                guard let productID = CoorditThreadProductID(rawValue: product.id) else { return nil }
                return CoorditThreadProduct(
                    id: product.id,
                    displayName: product.displayName,
                    displayPrice: product.displayPrice,
                    threadAmount: productID.threadAmount
                )
            }
            .sorted { $0.threadAmount < $1.threadAmount }
    }

    func purchase(productID: String, appAccountToken: UUID) async throws -> CoorditThreadStorePurchaseResult {
        guard let product = productsByID[productID], product.type == .consumable else {
            throw CoorditThreadPurchaseError.productsUnavailable
        }
        let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
        switch result {
        case .success(let verification):
            return map(verification)
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .unverified
        }
    }

    func unfinishedTransactions() async -> [CoorditThreadStorePurchaseResult] {
        var results: [CoorditThreadStorePurchaseResult] = []
        for await verification in Transaction.unfinished {
            if Task.isCancelled { break }
            results.append(map(verification))
        }
        return results
    }

    func transactionUpdates() -> AsyncStream<CoorditThreadStorePurchaseResult> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                for await verification in Transaction.updates {
                    if Task.isCancelled { break }
                    continuation.yield(map(verification))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func map(
        _ verification: VerificationResult<Transaction>
    ) -> CoorditThreadStorePurchaseResult {
        switch verification {
        case .unverified:
            return .unverified
        case .verified(let transaction):
            guard
                transaction.productType == .consumable,
                CoorditThreadProductID(rawValue: transaction.productID) != nil
            else {
                return .unverified
            }
            return .verified(
                CoorditThreadStoreTransaction(
                    id: String(transaction.id),
                    diagnosticLabel: "transaction",
                    productID: transaction.productID,
                    appAccountToken: transaction.appAccountToken,
                    jwsRepresentation: verification.jwsRepresentation,
                    finish: { await transaction.finish() }
                )
            )
        }
    }
}

enum CoorditThreadPurchaseError: LocalizedError {
    case productsUnavailable
    case accountUnavailable
    case invalidTransaction
    case balanceMismatch

    var errorDescription: String? {
        switch self {
        case .productsUnavailable:
            "App Store 상품 정보를 불러올 수 없어요. 다시 시도해 주세요."
        case .accountUnavailable:
            "로그인 계정을 확인한 뒤 다시 시도해 주세요."
        case .invalidTransaction:
            "구매 정보를 확인할 수 없어요."
        case .balanceMismatch:
            "서버 잔액 반영을 확인하지 못했어요. 다시 시도해 주세요."
        }
    }
}

enum CoorditThreadPurchaseState: Equatable {
    case idle
    case loadingProducts
    case ready
    case purchasing(productID: String)
    case pending
    case userCancelled
    case credited(threadAmount: Int)
    case alreadyCredited
    case failed(message: String)

    var message: String? {
        switch self {
        case .idle:
            nil
        case .loadingProducts:
            "App Store 상품 정보를 불러오고 있어요."
        case .ready:
            nil
        case .purchasing:
            "구매를 확인하고 있어요."
        case .pending:
            "구매 승인을 기다리고 있어요. 승인 후 자동으로 반영돼요."
        case .userCancelled:
            "구매를 취소했어요."
        case .credited(let threadAmount):
            "실타래 \(threadAmount)개를 충전했어요."
        case .alreadyCredited:
            "이미 반영된 구매를 확인했어요."
        case .failed(let message):
            message
        }
    }

    var blocksPurchases: Bool {
        switch self {
        case .loadingProducts, .purchasing:
            true
        default:
            false
        }
    }
}

@MainActor
final class CoorditThreadPurchaseService: ObservableObject {
    typealias VerifyPurchase = (String) async throws -> CoorditAppleIapSettlement
    typealias RefreshBalance = () async throws -> Int

    @Published private(set) var products: [CoorditThreadProduct] = []
    @Published private(set) var state: CoorditThreadPurchaseState = .idle
    @Published private(set) var settledBalance: Int?
    @Published private(set) var sanitizedEvents: [String] = []

    private let storefront: any CoorditThreadStorefront
    private var activeAccountID: UUID?
    private var verifyPurchase: VerifyPurchase?
    private var refreshBalance: RefreshBalance?
    private var updatesTask: Task<Void, Never>?
    private var processingTransactionIDs: Set<String> = []
    private var completedTransactionIDs: Set<String> = []

    convenience init() {
        self.init(storefront: Self.defaultStorefront())
    }

    init(storefront: any CoorditThreadStorefront) {
        self.storefront = storefront
#if DEBUG
        if let reporting = storefront as? any CoorditThreadPurchaseFixtureReporting {
            reporting.bindFixtureEventSink { [weak self] event in
                self?.record(event)
            }
        }
#endif
    }

    var displayProducts: [CoorditThreadProduct] {
        if products.isEmpty {
            return CoorditThreadProductID.allCases.map {
                CoorditThreadProduct(
                    id: $0.rawValue,
                    displayName: "\($0.threadAmount) 실타래",
                    displayPrice: "—",
                    threadAmount: $0.threadAmount
                )
            }
        }
        return products
    }

    var isReady: Bool {
        products.count == CoorditThreadProductID.allCases.count && activeAccountID != nil
    }

    var fixtureReceipt: String {
        sanitizedEvents.joined(separator: "|")
    }

    func canPurchase(_ product: CoorditThreadProduct) -> Bool {
        isReady
            && !state.blocksPurchases
            && products.contains(where: { $0.id == product.id })
    }

    func activate(
        accountID: UUID,
        verifyPurchase: @escaping VerifyPurchase,
        refreshBalance: @escaping RefreshBalance
    ) async {
        if activeAccountID == accountID, updatesTask != nil, isReady {
            return
        }

        deactivate(clearProducts: true)
        activeAccountID = accountID
        self.verifyPurchase = verifyPurchase
        self.refreshBalance = refreshBalance
        settledBalance = nil
        sanitizedEvents = []
        state = .loadingProducts
        record("products-request:\(CoorditThreadProductID.allCases.count)")

        do {
            products = try await storefront.loadProducts()
            guard Set(products.map(\.id)) == Set(CoorditThreadProductID.allCases.map(\.rawValue)) else {
                throw CoorditThreadPurchaseError.productsUnavailable
            }
            record("products-loaded:\(products.count)")
            state = .ready
            listenForTransactionUpdates()
            await reprocessUnfinishedTransactions()
        } catch is CancellationError {
            return
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func markAccountUnavailable() {
        deactivate(clearProducts: true)
        state = .failed(message: CoorditThreadPurchaseError.accountUnavailable.localizedDescription)
    }

    func deactivate(clearProducts: Bool = false) {
        updatesTask?.cancel()
        updatesTask = nil
        activeAccountID = nil
        verifyPurchase = nil
        refreshBalance = nil
        processingTransactionIDs.removeAll()
        completedTransactionIDs.removeAll()
        settledBalance = nil
        if clearProducts {
            products = []
            state = .idle
        }
    }

    func purchase(_ product: CoorditThreadProduct) async {
        guard let accountID = activeAccountID, canPurchase(product) else { return }
        state = .purchasing(productID: product.id)
        record("purchase-request:\(product.id)")
        record("app-account-token:present")

        do {
            let result = try await storefront.purchase(
                productID: product.id,
                appAccountToken: accountID
            )
            await handle(result, source: "purchase")
        } catch is CancellationError {
            state = .ready
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func reprocessUnfinishedTransactions() async {
        guard activeAccountID != nil else { return }
        let unfinished = await storefront.unfinishedTransactions()
        for result in unfinished {
            guard !Task.isCancelled else { return }
            if case .verified(let transaction) = result {
                record("unfinished:\(transaction.diagnosticLabel)")
            }
            await handle(result, source: "unfinished")
        }
    }

    private func listenForTransactionUpdates() {
        updatesTask?.cancel()
        let updates = storefront.transactionUpdates()
        updatesTask = Task { @MainActor [weak self] in
            for await result in updates {
                guard !Task.isCancelled, let self else { return }
                await handle(result, source: "update")
            }
        }
    }

    private func handle(_ result: CoorditThreadStorePurchaseResult, source: String) async {
        switch result {
        case .userCancelled:
            record("purchase-result:cancelled")
            state = .userCancelled
        case .pending:
            record("purchase-result:pending")
            state = .pending
        case .unverified:
            record("purchase-result:unverified")
            state = .failed(message: CoorditThreadPurchaseError.invalidTransaction.localizedDescription)
        case .verified(let transaction):
            await settle(transaction, source: source)
        }
    }

    private func settle(_ transaction: CoorditThreadStoreTransaction, source: String) async {
        guard
            let accountID = activeAccountID,
            transaction.appAccountToken == accountID,
            let productID = CoorditThreadProductID(rawValue: transaction.productID),
            !transaction.jwsRepresentation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let verifyPurchase,
            let refreshBalance
        else {
            record("purchase-result:unverified")
            state = .failed(message: CoorditThreadPurchaseError.invalidTransaction.localizedDescription)
            return
        }
        guard !completedTransactionIDs.contains(transaction.id) else {
            record("transaction-deduped:\(source)")
            return
        }
        guard processingTransactionIDs.insert(transaction.id).inserted else {
            record("transaction-in-flight:\(source)")
            return
        }

        record("transaction-verified:\(transaction.diagnosticLabel)")
        do {
            record("backend-post:jws-nonempty")
            let settlement = try await verifyPurchase(transaction.jwsRepresentation)
            record("backend-response:\(settlement.httpStatusCode):\(settlement.status.rawValue)")

            let serverBalance = try await refreshBalance()
            guard serverBalance == settlement.availableThreads else {
                throw CoorditThreadPurchaseError.balanceMismatch
            }
            settledBalance = serverBalance
            record("balance-refresh:\(serverBalance)")

            await transaction.finish()
            completedTransactionIDs.insert(transaction.id)
            processingTransactionIDs.remove(transaction.id)

            switch settlement.status {
            case .credited:
                state = .credited(threadAmount: productID.threadAmount)
            case .alreadyCredited:
                state = .alreadyCredited
            }
        } catch is CancellationError {
            processingTransactionIDs.remove(transaction.id)
        } catch {
            processingTransactionIDs.remove(transaction.id)
            state = .failed(message: error.localizedDescription)
        }
    }

    private func record(_ event: String) {
        sanitizedEvents.append(event)
    }

    private static func defaultStorefront() -> any CoorditThreadStorefront {
#if DEBUG
        if let scenario = CoorditThreadPurchaseFixtureScenario.launch() {
            return CoorditThreadPurchaseFixtureStorefront(scenario: scenario)
        }
#endif
        return CoorditStoreKitThreadStorefront()
    }
}

#if DEBUG
enum CoorditThreadPurchaseFixtureScenario: String {
    case credited
    case alreadyCredited = "already_credited"
    case cancelled
    case pending
    case unverified
    case backendError = "backend_error"

    static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        guard
            let marker = arguments.firstIndex(of: "--coordit-storekit-fixture"),
            arguments.indices.contains(arguments.index(after: marker))
        else {
            return nil
        }
        return Self(rawValue: arguments[arguments.index(after: marker)])
    }
}

@MainActor
private final class CoorditThreadPurchaseFinishProbe {
    private var counts: [String: Int] = [:]
    private var eventSink: @MainActor @Sendable (String) -> Void = { _ in }

    func bindEventSink(
        _ sink: @escaping @MainActor @Sendable (String) -> Void
    ) {
        eventSink = sink
    }

    func record(transactionID: String) {
        let count = (counts[transactionID] ?? 0) + 1
        counts[transactionID] = count
        eventSink("fixture-finish:\(transactionID):count=\(count)")
    }
}

@MainActor
final class CoorditThreadPurchaseFixtureStorefront:
    CoorditThreadStorefront,
    CoorditThreadPurchaseFixtureReporting
{
    private let scenario: CoorditThreadPurchaseFixtureScenario
    private let finishProbe = CoorditThreadPurchaseFinishProbe()

    func bindFixtureEventSink(
        _ sink: @escaping @MainActor @Sendable (String) -> Void
    ) {
        finishProbe.bindEventSink(sink)
    }

    init(scenario: CoorditThreadPurchaseFixtureScenario) {
        self.scenario = scenario
    }

    func loadProducts() async throws -> [CoorditThreadProduct] {
        [
            CoorditThreadProduct(
                id: CoorditThreadProductID.pack5.rawValue,
                displayName: "StoreKit 실타래 5개",
                displayPrice: "₩1,500",
                threadAmount: 5
            ),
            CoorditThreadProduct(
                id: CoorditThreadProductID.pack10.rawValue,
                displayName: "StoreKit 실타래 10개",
                displayPrice: "₩2,500",
                threadAmount: 10
            ),
            CoorditThreadProduct(
                id: CoorditThreadProductID.pack20.rawValue,
                displayName: "StoreKit 실타래 20개",
                displayPrice: "₩4,000",
                threadAmount: 20
            ),
        ]
    }

    func purchase(productID: String, appAccountToken: UUID) async throws -> CoorditThreadStorePurchaseResult {
        guard appAccountToken.uuidString == "00000000-0000-4000-8000-000000000010" else {
            throw CoorditThreadPurchaseError.invalidTransaction
        }
        switch scenario {
        case .credited:
            return .verified(
                fixtureTransaction(
                    id: "credited-10",
                    productID: productID,
                    accountID: appAccountToken
                )
            )
        case .alreadyCredited:
            return .verified(
                fixtureTransaction(
                    id: "already-credited-10",
                    productID: productID,
                    accountID: appAccountToken
                )
            )
        case .cancelled:
            return .userCancelled
        case .pending:
            return .pending
        case .unverified:
            return .unverified
        case .backendError:
            return .verified(
                fixtureTransaction(
                    id: "backend-error-10",
                    productID: productID,
                    accountID: appAccountToken
                )
            )
        }
    }

    func unfinishedTransactions() async -> [CoorditThreadStorePurchaseResult] {
        guard scenario == .alreadyCredited else { return [] }
        return [
            .verified(
                fixtureTransaction(
                    id: "unfinished-10",
                    productID: CoorditThreadProductID.pack10.rawValue,
                    accountID: UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
                )
            ),
        ]
    }

    func transactionUpdates() -> AsyncStream<CoorditThreadStorePurchaseResult> {
        AsyncStream { $0.finish() }
    }

    private func fixtureTransaction(
        id: String,
        productID: String,
        accountID: UUID
    ) -> CoorditThreadStoreTransaction {
        let finishProbe = finishProbe
        return CoorditThreadStoreTransaction(
            id: id,
            diagnosticLabel: id,
            productID: productID,
            appAccountToken: accountID,
            jwsRepresentation: "fixture.header.payload.signature",
            finish: {
                await finishProbe.record(transactionID: id)
            }
        )
    }
}
#endif
#endif
