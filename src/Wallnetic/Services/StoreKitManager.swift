import Foundation
import StoreKit
import SwiftUI

/// Manages In-App Purchase for Wallnetic Pro
class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    static let proProductID = "com.wallnetic.app.pro"

    @Published var isPro = false
    @Published var proProduct: Product?
    @Published var purchaseState: PurchaseState = .idle

    enum PurchaseState {
        case idle, loading, purchasing, purchased, failed(String)
    }

    private init() {
        Task { await loadProducts() }
        Task { await listenForTransactions() }
    }

    // MARK: - Products

    @MainActor
    func loadProducts() async {
        purchaseState = .loading
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
            purchaseState = .idle
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Purchase

    @MainActor
    func purchasePro() async {
        guard let product = proProduct else { return }

        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                isPro = true
                purchaseState = .purchased
                await transaction.finish()
            case .pending:
                purchaseState = .idle
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if let transaction = try? checkVerified(result),
                   transaction.productID == Self.proProductID {
                    isPro = true
                    purchaseState = .purchased
                }
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.proProductID {
                await MainActor.run { isPro = true }
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified: throw StoreError.verificationFailed
        }
    }
}

enum StoreError: LocalizedError {
    case verificationFailed
    var errorDescription: String? { "Purchase verification failed" }
}
