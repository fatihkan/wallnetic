import SwiftUI
import StoreKit

/// The tip offer (#337). It appears in the Support Wallnetic window and, now
/// and then, as a sheet on the main window (``TipPromptManager``). Tips unlock
/// nothing, and the copy says so.
struct TipJarView: View {
    enum Mode {
        /// Opened deliberately from the menu bar or Settings > About.
        case window
        /// Offered unprompted; adds Not Now and Don't Ask Again.
        case prompt
    }

    let mode: Mode
    var onNotNow: () -> Void = {}
    var onDontAskAgain: () -> Void = {}
    let onClose: () -> Void

    @ObservedObject private var tipJar = TipJar.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 36))
                .foregroundColor(.pink)
                .accessibilityHidden(true)
            Text("Support Wallnetic")
                .font(.title2)
                .fontWeight(.semibold)

            if tipJar.purchaseState == .thanked {
                Text("Thank you! Your tip helps keep Wallnetic free and growing.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("Wallnetic is free and open source. If it brightens your desktop, a tip helps keep it going. Tips don't unlock anything.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                tipButtons
                status
                footer
            }
        }
        .padding(24)
        .frame(width: 380)
        .task { await tipJar.loadProducts() }
        .onDisappear { tipJar.resetPurchaseState() }
    }

    @ViewBuilder
    private var tipButtons: some View {
        if tipJar.products.isEmpty {
            Text("Tips aren't available right now.")
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: 8) {
                ForEach(tipJar.products, id: \.id) { product in
                    Button {
                        Task { await tipJar.purchase(product) }
                    } label: {
                        HStack {
                            Text(product.displayName)
                            Spacer()
                            if tipJar.purchaseState == .purchasing(productID: product.id) {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(product.displayPrice)
                                    .monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(isPurchasing)
                    .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch tipJar.purchaseState {
        case .pending:
            Text("Waiting for approval. The tip completes once it is approved.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch mode {
        case .prompt:
            HStack {
                Button("Don't Ask Again", action: onDontAskAgain)
                Spacer()
                Button("Not Now", action: onNotNow)
                    .keyboardShortcut(.cancelAction)
            }
        case .window:
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var isPurchasing: Bool {
        if case .purchasing = tipJar.purchaseState { return true }
        return false
    }
}

/// The Support Wallnetic window, opened from the menu bar and Settings > About.
struct SupportWindowView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TipJarView(mode: .window, onClose: { dismiss() })
            .onAppear {
                // Same as SettingsView (#228): with Hide Dock icon on, the app
                // must become regular and active for this window to take key.
                if NSApp.activationPolicy() == .accessory {
                    NSApp.setActivationPolicy(.regular)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
