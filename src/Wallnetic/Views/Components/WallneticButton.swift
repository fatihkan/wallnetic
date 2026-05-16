import SwiftUI

/// 2026 Liquid Glass button family. Replaces SwiftUI's `.borderedProminent`
/// which leaks system chrome into our dark cinematic surfaces.
///
/// Three tiers:
///  * `.primary`   — accent gradient + inner highlight stroke + soft glow.
///                   One per surface; bound to ⌘↩.
///  * `.ghost`     — liquid-glass capsule with neutral tint.
///  * `.cancel`    — chromeless minimal; bound to ⎋.
enum WallneticButton {
    static func primary(
        _ title: String,
        icon: String? = nil,
        accent: Color = .accentColor,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(Typo.button)
                    .tracking(Typo.buttonTracking)
            }
        }
        .buttonStyle(LiquidPrimaryButtonStyle(accent: accent, isEnabled: isEnabled))
        .disabled(!isEnabled)
        .keyboardShortcut(.return)
    }

    static func ghost(
        _ title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xxs + 2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .buttonStyle(LiquidGhostButtonStyle())
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

// MARK: - Primary (Liquid Glass + accent)

private struct LiquidPrimaryButtonStyle: ButtonStyle {
    let accent: Color
    let isEnabled: Bool
    @State private var wobble: CGFloat = 1.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? .black : .white.opacity(0.35))
            .padding(.horizontal, Space.lg)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(isEnabled
                              ? AnyShapeStyle(LinearGradient(
                                    colors: [accent, accent.opacity(0.75)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color.white.opacity(0.06)))

                    // Top inner highlight — light catching the lens edge
                    Capsule(style: .continuous)
                        .strokeBorder(LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isEnabled ? 0.55 : 0.10), location: 0),
                                .init(color: .white.opacity(0), location: 0.55),
                                .init(color: .black.opacity(isEnabled ? 0.20 : 0.05), location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ), lineWidth: 0.75)
                }
            )
            .shadow(
                color: isEnabled ? accent.opacity(configuration.isPressed ? 0.20 : 0.55) : .clear,
                radius: configuration.isPressed ? 4 : 12,
                y: configuration.isPressed ? 1 : 5
            )
            // Press: compress to 0.96. Release: bouncy spring back through
            // 1.0 → ~1.025 → 1.0. Wobble is purely visual; the action
            // already fired on touch-up.
            .scaleEffect(configuration.isPressed ? 0.96 : wobble)
            .onChange(of: configuration.isPressed) { newPressed in
                guard isEnabled else { return }
                if !newPressed {
                    wobble = 1.025
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                        wobble = 1.0
                    }
                }
            }
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

// MARK: - Ghost (Liquid Glass neutral)

private struct LiquidGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, Space.md)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.06 : 0.09))
                    Capsule(style: .continuous)
                        .strokeBorder(LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.20), location: 0),
                                .init(color: .white.opacity(0.05), location: 0.5),
                                .init(color: .black.opacity(0.25), location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ), lineWidth: 0.6)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Liquid Glass Text Field

/// Replaces `.textFieldStyle(.roundedBorder)` which renders macOS chrome.
struct WallneticTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var accent: Color = .accentColor
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(focused ? accent : .white.opacity(0.4))
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .font(Typo.body)
                .focused($focused)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.white.opacity(focused ? 0.08 : 0.04))
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(LinearGradient(
                        stops: [
                            .init(color: focused ? accent.opacity(0.55) : .white.opacity(0.18), location: 0),
                            .init(color: focused ? accent.opacity(0.25) : .white.opacity(0.04), location: 0.5),
                            .init(color: focused ? accent.opacity(0.45) : .black.opacity(0.3), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ), lineWidth: focused ? 1 : 0.6)
            }
        )
        .focusHalo(focused, radius: Radius.control, accent: accent)
        .animation(.easeOut(duration: 0.16), value: focused)
    }
}
