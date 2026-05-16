import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        ZStack {
            // Full bleed dark backdrop replacing the system Form chrome
            Color(red: 0.04, green: 0.05, blue: 0.09)
                .ignoresSafeArea()
            RadialGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                center: .topLeading, startRadius: 5, endRadius: 360
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                Divider()
                    .overlay(Color.white.opacity(0.06))
                detail
            }
        }
        .frame(width: 880, height: 560)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.4)
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsSection.allCases.filter { !$0.isFooter }) { section in
                        SidebarRow(section: section, isSelected: selection == section) {
                            withAnimation(.easeOut(duration: 0.18)) { selection = section }
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)

                    ForEach(SettingsSection.allCases.filter { $0.isFooter }) { section in
                        SidebarRow(section: section, isSelected: selection == section) {
                            withAnimation(.easeOut(duration: 0.18)) { selection = section }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)

            // Version badge
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
                    .shadow(color: .green.opacity(0.6), radius: 3)
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .frame(width: 220)
    }

    // MARK: - Detail Pane

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: selection.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selection.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(selection.accent.opacity(0.18))
                    )
                    .shadow(color: selection.accent.opacity(0.4), radius: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(selection.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(selection.tagline)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 18)

            Divider()
                .overlay(LinearGradient(
                    colors: [.clear, selection.accent.opacity(0.35), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 0.5)

            ZStack {
                content
                    .scrollContentBackground(.hidden)
            }
            .id(selection)
            .transition(.asymmetric(
                insertion: .offset(y: 8).combined(with: .opacity),
                removal: .opacity
            ))
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:    GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .playback:   PlaybackSettingsView()
        case .effects:    EffectsSettingsView()
        case .schedule:   TimeOfDaySettingsView()
        case .spaces:     SpaceSettingsView()
        case .smartTags:  SmartTaggingSettingsView()
        case .display:    DisplaySettingsView()
        case .notifications: NotificationSettingsView()
        case .about:      AboutSettingsView()
        }
    }
}

// MARK: - Sections

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, playback, effects, schedule, spaces, smartTags, display, notifications, about

    var id: String { rawValue }
    var isFooter: Bool { self == .notifications || self == .about }

    var title: String {
        switch self {
        case .general:       return "General"
        case .appearance:    return "Appearance"
        case .playback:      return "Playback"
        case .effects:       return "Effects"
        case .schedule:      return "Schedule"
        case .spaces:        return "Spaces"
        case .smartTags:     return "Smart Tags"
        case .display:       return "Display"
        case .notifications: return "Notifications"
        case .about:         return "About"
        }
    }

    var tagline: String {
        switch self {
        case .general:       return "App-wide behavior and library location."
        case .appearance:    return "Theme, accent, and dynamic colors."
        case .playback:      return "Power, performance, and pause rules."
        case .effects:       return "Live wallpaper post-processing."
        case .schedule:      return "Time-of-day rotations."
        case .spaces:        return "Per-Space wallpaper assignments."
        case .smartTags:     return "Local Ollama Vision auto-tagging."
        case .display:       return "Per-monitor mode and tracking."
        case .notifications: return "Toggle alert categories."
        case .about:         return "Version, credits, and links."
        }
    }

    var icon: String {
        switch self {
        case .general:       return "gear"
        case .appearance:    return "paintbrush.fill"
        case .playback:      return "play.fill"
        case .effects:       return "wand.and.stars"
        case .schedule:      return "clock.arrow.2.circlepath"
        case .spaces:        return "square.stack.3d.up.fill"
        case .smartTags:     return "tag.fill"
        case .display:       return "display"
        case .notifications: return "bell.fill"
        case .about:         return "info.circle.fill"
        }
    }

    var accent: Color {
        switch self {
        case .general:       return Color(red: 0.42, green: 0.71, blue: 1.00)
        case .appearance:    return Color(red: 1.00, green: 0.45, blue: 0.72)
        case .playback:      return Color(red: 0.40, green: 0.95, blue: 0.55)
        case .effects:       return Color(red: 0.85, green: 0.55, blue: 1.00)
        case .schedule:      return Color(red: 1.00, green: 0.75, blue: 0.35)
        case .spaces:        return Color(red: 0.55, green: 0.80, blue: 1.00)
        case .smartTags:     return Color(red: 0.45, green: 0.95, blue: 0.95)
        case .display:       return Color(red: 0.65, green: 0.85, blue: 0.50)
        case .notifications: return Color(red: 1.00, green: 0.60, blue: 0.45)
        case .about:         return Color.white.opacity(0.85)
        }
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? section.accent : .white.opacity(hover ? 0.7 : 0.45))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? section.accent.opacity(0.18) : Color.clear)
                    )

                Text(section.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(hover ? 0.85 : 0.6))

                Spacer()

                if isSelected {
                    Circle()
                        .fill(section.accent)
                        .frame(width: 4, height: 4)
                        .shadow(color: section.accent.opacity(0.7), radius: 3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.06) : (hover ? Color.white.opacity(0.03) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

#Preview {
    SettingsView()
        .environmentObject(WallpaperManager.shared)
}
