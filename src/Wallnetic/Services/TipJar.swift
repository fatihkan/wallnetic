import Foundation
import StoreKit
import os.log

private let logger = Logger(subsystem: "com.wallnetic.app", category: "TipJar")

/// Optional tips through App Store in-app purchase (#337).
///
/// Tips are consumable products that unlock nothing; App Review Guideline
/// 3.1.1 allows tipping the developer through in-app purchase. StoreKit 2
/// verifies every transaction on device and Wallnetic sends nothing to a
/// server of its own, so the App Privacy answer stays Data Not Collected.
///
/// The direct-download DMG is ad-hoc signed and comes from outside the App
/// Store, so StoreKit returns no products there. Every tip entry point checks
/// ``isAvailable`` and stays hidden in that build.
@MainActor
final class TipJar: ObservableObject {
    static let shared = TipJar()

    /// Product identifiers as configured in App Store Connect.
    static let productIDs = [
        "com.wallnetic.app.tip.small",
        "com.wallnetic.app.tip.medium",
        "com.wallnetic.app.tip.large",
    ]

    enum PurchaseState: Equatable {
        case idle
        case purchasing(productID: String)
        /// Waiting for approval, for example Ask to Buy.
        case pending
        case thanked
        case failed(String)
    }

    /// Tip products, cheapest first. Empty until StoreKit answers, and for
    /// good in builds that do not come from the App Store.
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseState: PurchaseState = .idle

    var isAvailable: Bool { !products.isEmpty }

    private var updatesTask: Task<Void, Never>?
    private var isLoading = false

    private init() {}

    /// Called once at launch. Finishes tips that completed while the app was
    /// not watching (an approved Ask to Buy, an interrupted purchase) and
    /// loads the prices the entry points need.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await loadProducts() }
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
            if loaded.isEmpty { logger.info("No tip products from the App Store") }
        } catch {
            logger.info("Tip products unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    func purchase(_ product: Product) async {
        if case .purchasing = purchaseState { return }
        purchaseState = .purchasing(productID: product.id)
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseState = .failed("The App Store could not verify this purchase.")
                    return
                }
                await transaction.finish()
                TipPromptManager.shared.recordTip()
                purchaseState = .thanked
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// Clears a finished or failed purchase when the tip sheet closes, so the
    /// next visit starts from the offer again.
    func resetPurchaseState() {
        if case .purchasing = purchaseState { return }
        purchaseState = .idle
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update,
              Self.productIDs.contains(transaction.productID) else { return }
        if transaction.revocationDate == nil {
            TipPromptManager.shared.recordTip()
            if purchaseState == .pending { purchaseState = .thanked }
        }
        await transaction.finish()
    }
}
