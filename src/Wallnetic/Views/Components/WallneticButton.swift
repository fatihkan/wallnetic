import SwiftUI

/// Wallnetic's signature buttons. Used in sheets, onboarding, and any
/// place a plain SwiftUI `.borderedProminent` would otherwise leak macOS
/// chrome into the dark cinematic surfaces.
///
/// Three tiers:
///  * `.primary`   — accent-glow CTA (one per surface ideally)
///  * `.ghost`     — translucent secondary action
///  * `.cancel`    — minimal, no chrome
enum WallneticButton {
    static func primary(
        _ title: String,
        icon: String? = nil,
        accent: Color = .accentColor,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.3)
            }
        }
        .buttonStyle(WallneticPrimaryButtonStyle(accent: accent, isEnabled: isEnabled))
        .disabled(!isEnabled)
        .keyboardShortcut(.return)
    }

    static func ghost(
        _ title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .buttonStyle(WallneticGhostButtonStyle())
    }

    static func cancel(
        _ title: String = "Cancel",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape)
    }
}

// MARK: - Primary (Accent Glow)

private struct WallneticPrimaryButtonStyle: ButtonStyle {
    let accent: Color
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? .black : .white.opacity(0.35))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    Capsule()
                        .fill(isEnabled
                              ? AnyShapeStyle(LinearGradient(
                                    colors: [accent, accent.opacity(0.85)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color.white.opacity(0.06)))
                    Capsule()
                        .stroke(isEnabled ? accent.opacity(0.55) : .white.opacity(0.08), lineWidth: 0.5)
                }
            )
            .shadow(
                color: isEnabled ? accent.opacity(configuration.isPressed ? 0.15 : 0.45) : .clear,
                radius: configuration.isPressed ? 4 : 10,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Ghost (Glass Secondary)

private struct WallneticGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(configuration.isPressed ? 0.05 : 0.08))
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Wallnetic Text Field

/// Dark glass text field — replaces `.textFieldStyle(.roundedBorder)` which
/// renders macOS chrome.
struct WallneticTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var accent: Color = .accentColor
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(focused ? 0.07 : 0.04))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        focused ? accent.opacity(0.5) : Color.white.opacity(0.1),
                        lineWidth: focused ? 1 : 0.5
                    )
            }
        )
        .shadow(color: focused ? accent.opacity(0.25) : .clear, radius: focused ? 6 : 0)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}
