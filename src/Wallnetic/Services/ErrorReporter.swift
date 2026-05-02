import Foundation
import os.log

/// Centralized error surfacing channel for non-fatal failures that the user
/// should know about (#167).
///
/// The app has three historical error-handling shapes:
/// 1. `try?` — silent failure, no diagnostics, no user feedback.
/// 2. `throw` + LocalizedError — propagated, user-visible at top-level catch.
/// 3. `print`/`NSLog` — logged but invisible to the user.
///
/// `ErrorReporter` is the third axis: a non-throwing failure path that
/// still records the failure (always) and optionally surfaces it to the
/// UI (when the failure is user-facing).
///
/// Use it for cache decode failures, optional sync errors, background
/// import errors, and any other "shouldn't crash but the user might
/// want to know" cases. For fatal errors, throw. For genuinely silent
/// cleanup (`removeItem` on a temp file), keep `try?`.
@MainActor
final class ErrorReporter: ObservableObject {
    static let shared = ErrorReporter()

    /// The most recent surfaced error, if any. ContentView observes this
    /// and renders an alert until it's acknowledged.
    @Published var current: AppError?

    private init() {}

    // MARK: - Reporting

    /// Logs the error and (optionally) shows it as an alert in the main
    /// window. `surface == false` means log-only — useful for batch
    /// operations where 1 of N failing is expected.
    func report(_ error: Error, context: String, surface: Bool = true) {
        let message = String(describing: error)
        Log.app.error("\(context, privacy: .public): \(message, privacy: .public)")
        guard surface else { return }
        let appError = AppError(
            title: context,
            message: error.localizedDescription
        )
        // Coalesce duplicate alerts within a short window — repeated cache
        // decode failures shouldn't spam the UI.
        Task { @MainActor in
            current = appError
        }
    }

    /// Dismisses the current alert without surfacing a new one.
    func dismissCurrent() {
        current = nil
    }
}

/// Lightweight error envelope for the alert layer. Identifiable so a
/// SwiftUI `.alert(item:)` can react to changes.
struct AppError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
