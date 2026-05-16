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
            .ignoresSafeArea(.all, edges: .top)  // claim the title-bar zone
        }
        .frame(width: 820, height: 540)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark *inhabits* the title-bar row — no wasted clearance.
            // Traffic lights occupy 0-66px from the leading edge; we offset
            // the text so it never collides with them. ~28pt total height
            // matches macOS's natural title-bar metrics.
            HStack(spacing: 0) {
                Text("Wallnetic")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .tracking(-0.1)
                Text(" Settings")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(-0.1)
                Spacer()
            }
            .padding(.leading, 80)  // traffic-light clearance
            .padding(.trailing, Space.sm)
            .frame(height: 28)
            .padding(.bottom, Space.xs)

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
            HStack(spacing: Space.xxs + 2) {
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
                    .shadow(color: .green.opacity(0.65), radius: 3)
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .styledData(color: .white.opacity(0.5))
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, Space.lg + 2)
            .padding(.bottom, Space.md + 2)
        }
        .frame(width: 224)
        .background(
            // Translucent over content — Liquid Glass sidebar
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.black.opacity(0.32))
                // Inner accent wash
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.08), .clear],
                    startPoint: .topLeading, endPoint: .center
                )
            }
        )
        .overlay(alignment: .trailing) {
            // Right-edge refractive hairline
            Rectangle()
                .fill(LinearGradient(
                    colors: [.white.opacity(0.04), .white.opacity(0.12), .white.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 0.5)
        }
    }

    // MARK: - Detail Pane

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title-bar stripe — matches sidebar wordmark row height so the
            // window top is one continuous horizontal band. Empty by design;
            // gives the eye a clean rest above the section header.
            Color.clear.frame(height: 28)

            HStack(spacing: Space.sm) {
                Image(systemName: selection.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(selection.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        ZStack {
                            Circle().fill(selection.accent.opacity(0.16))
                            Circle().strokeBorder(selection.accent.opacity(0.30), lineWidth: 0.5)
                        }
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(selection.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(-0.2)
                    Text(selection.tagline)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))
                }

                Spacer()
            }
            .padding(.horizontal, Space.xl + 4)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.md - 2)

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
            HStack(spacing: Space.xs + 2) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.accent, style: .continuous)
                            .fill(section.accent.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.accent, style: .continuous)
                                    .strokeBorder(section.accent.opacity(0.4), lineWidth: 0.5)
                            )
                            .shadow(color: section.accent.opacity(0.45), radius: 4)
                    }
                    Image(systemName: section.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .white.opacity(hover ? 0.75 : 0.45))
                }
                .frame(width: 22, height: 22)

                Text(section.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(hover ? 0.85 : 0.6))
                    .tracking(isSelected ? 0.2 : 0)

                Spacer()

                if isSelected {
                    Circle()
                        .fill(section.accent)
                        .frame(width: 4, height: 4)
                        .shadow(color: section.accent.opacity(0.8), radius: 4)
                }
            }
            .padding(.horizontal, Space.sm - 2)
            .padding(.vertical, Space.xs - 1)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                        RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                            .strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.16), .white.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            ), lineWidth: 0.5)
                    } else if hover {
                        RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .suppressFocusRing()
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

#Preview {
    SettingsView()
        .environmentObject(WallpaperManager.shared)
}
