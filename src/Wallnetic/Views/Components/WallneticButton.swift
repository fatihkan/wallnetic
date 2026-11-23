import SwiftUI

/// The app's sheet and onboarding buttons, built on the system button
/// styles so they match Trim, Optimize and the rest of macOS, and take
/// Liquid Glass from the system on macOS 26 (#343 B3b).
///
/// Three tiers:
///  * `.primary`   — the prominent default button. One per surface; ⏎.
///  * `.ghost`     — a bordered secondary button.
///  * `.cancel`    — a bordered button bound to ⎋.
enum WallneticButton {
    static func primary(
        _ title: String,
        icon: String? = nil,
        accent: Color = .accentColor,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label(title, icon: icon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(accent)
        .disabled(!isEnabled)
        .keyboardShortcut(.defaultAction)
    }

    static func ghost(
        _ title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label(title, icon: icon)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    static func cancel(
        _ title: String = "Cancel",
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private static func label(_ title: String, icon: String?) -> some View {
        if let icon {
            Label(title, systemImage: icon)
        } else {
            Text(title)
        }
    }
}

// MARK: - Text Field

/// A single-line field for sheets, with the system's border and focus ring.
struct WallneticTextField: View {
    let placeholder: String
    @Binding var text: String
    /// Kept for call sites; the system field shows no leading icon.
    var icon: String? = nil
    var accent: Color = .accentColor
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .onSubmit { onSubmit?() }
    }
}
