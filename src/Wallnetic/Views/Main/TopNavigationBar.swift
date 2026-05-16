import SwiftUI

/// Top navigation tab
enum NavigationTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case explore = "Explore"
    case popular = "Popular"
    case discover = "Discover"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "safari.fill"
        case .popular: return "flame.fill"
        case .discover: return "globe"
        }
    }
}

/// Striking glass navigation bar with neon-glow tabs.
/// Phase C revision: gradient-underline active tab, frosted material
/// background, full search bar (not just an icon), uniform action button
/// chrome shared by Import + Settings.
struct TopNavigationBar: View {
    @Binding var selectedTab: NavigationTab
    @Binding var searchText: String
    @Binding var isImporting: Bool
    @Binding var showingPhotosImport: Bool
    @State private var isSearching = false
    @State private var hoveredTab: NavigationTab?
    @FocusState private var searchFocused: Bool
    var isScrolled: Bool = false

    var body: some View {
        ZStack {
            // LEFT: search
            HStack {
                searchControl
                    .frame(maxWidth: 240, alignment: .leading)
                Spacer()
            }

            // CENTER: logo + tabs
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .accentColor.opacity(0.45), radius: 8)

                HStack(spacing: 4) {
                    ForEach(NavigationTab.allCases) { tab in
                        tabButton(tab)
                    }
                }
            }

            // RIGHT: import + settings
            HStack(spacing: 10) {
                Spacer()

                Menu {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import video file…", systemImage: "film")
                    }
                    .keyboardShortcut("i", modifiers: .command)

                    Button {
                        showingPhotosImport = true
                    } label: {
                        Label("Create from Photos…", systemImage: "photo.on.rectangle.angled")
                    }
                } label: {
                    ActionChip(icon: "plus", accent: true)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 30, height: 30)

                if #available(macOS 14.0, *) {
                    SettingsLink {
                        ActionChip(icon: "gearshape.fill", accent: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(navBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .accentColor.opacity(isScrolled ? 0.25 : 0.05), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
        }
    }

    // MARK: - Background

    private var navBackground: some View {
        ZStack {
            // Frosted glass — stronger when content scrolls under
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isScrolled ? 0.85 : 0.5)
            // Dark tint underneath material so it never goes light
            Color.black.opacity(isScrolled ? 0.35 : 0.18)
        }
        .animation(.easeInOut(duration: Anim.medium), value: isScrolled)
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(_ tab: NavigationTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab

        Button {
            withAnimation(.spring(response: Anim.enter, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 10))
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .tracking(0.1)
                }
                .foregroundColor(isSelected ? .white : .white.opacity(isHovered ? 0.85 : 0.55))

                // Active gradient underline
                Capsule()
                    .fill(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.6)],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            : AnyShapeStyle(Color.clear)
                    )
                    .frame(width: isSelected ? 28 : 0, height: 2)
                    .shadow(color: .accentColor.opacity(0.6), radius: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                Capsule()
                    .fill(isHovered && !isSelected ? Color.white.opacity(0.05) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: Anim.micro)) { hoveredTab = h ? tab : nil }
        }
    }

    // MARK: - Search Control

    @ViewBuilder
    private var searchControl: some View {
        if isSearching {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .shadow(color: .accentColor.opacity(0.6), radius: 4)

                TextField("Search wallpapers…", text: $searchText, prompt:
                    Text("Search wallpapers…").foregroundColor(.white.opacity(0.32))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .focused($searchFocused)
                .frame(width: 170)

                Button {
                    withAnimation(.easeOut(duration: Anim.fast)) {
                        isSearching = false
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().stroke(Color.accentColor.opacity(0.45), lineWidth: 0.6)
                }
            )
            .shadow(color: .accentColor.opacity(0.25), radius: 6)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
            .onAppear { searchFocused = true }
        } else {
            Button {
                withAnimation(.easeOut(duration: Anim.normal)) { isSearching = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                    Text("Search")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer(minLength: 0)
                    Text("⌘F")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.28))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(width: 180)
                .background(
                    ZStack {
                        Capsule().fill(Color.white.opacity(0.04))
                        Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    }
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}

// MARK: - Action Chip

private struct ActionChip: View {
    let icon: String
    let accent: Bool
    @State private var hover = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(hover ? 1.0 : 0.75))
            .frame(width: 28, height: 28)
            .background(
                ZStack {
                    Circle().fill(
                        accent && hover
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color.accentColor.opacity(0.4), Color.accentColor.opacity(0.18)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.white.opacity(hover ? 0.12 : 0.06))
                    )
                    Circle().stroke(
                        accent && hover ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.12),
                        lineWidth: 0.5
                    )
                }
            )
            .shadow(
                color: accent && hover ? Color.accentColor.opacity(0.45) : .clear,
                radius: 8
            )
            .onHover { hover = $0 }
            .animation(.easeOut(duration: Anim.normal), value: hover)
    }
}
