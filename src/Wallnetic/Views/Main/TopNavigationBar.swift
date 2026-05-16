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
    @Namespace private var tabUnderlineNS
    @Environment(\.openWindow) private var openWindow
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

                Button {
                    openWindow(id: "settings")
                } label: {
                    ActionChip(icon: "gearshape.fill", accent: false)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .padding(.leading, 84)        // reserve traffic-light real estate
        .padding(.trailing, Space.md)
        .padding(.vertical, Space.xs + 2)
        .background(navBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.08), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 0.5)
        }
    }

    /// In-window toolbar background. Traffic lights overlay this strip;
    /// content scrolls beneath it. Glass intensifies as user scrolls.
    private var navBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isScrolled ? 0.92 : 0.65)
            Rectangle()
                .fill(Color.black.opacity(isScrolled ? 0.35 : 0.20))
        }
        .animation(.easeInOut(duration: Anim.medium), value: isScrolled)
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(_ tab: NavigationTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab

        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72, blendDuration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .tracking(0.1)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(isHovered ? 0.85 : 0.55))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                ZStack {
                    // Selected: soft glass pill with hairline stroke — no
                    // shouty underline, no accent color screaming
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .matchedGeometryEffect(id: "tabPill", in: tabUnderlineNS)
                        Capsule(style: .continuous)
                            .strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                startPoint: .top, endPoint: .bottom
                            ), lineWidth: 0.5)
                            .matchedGeometryEffect(id: "tabPillStroke", in: tabUnderlineNS)
                    } else if isHovered {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    }
                }
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
            .frame(width: 30, height: 30)
            .background(
                ZStack {
                    Circle()
                        .fill(
                            accent && hover
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.2)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.white.opacity(hover ? 0.10 : 0.05))
                        )
                    // Refractive stroke
                    Circle()
                        .strokeBorder(LinearGradient(
                            stops: [
                                .init(color: accent && hover ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.22), location: 0),
                                .init(color: .white.opacity(0.04), location: 0.55),
                                .init(color: .black.opacity(0.30), location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ), lineWidth: 0.75)
                }
            )
            .shadow(
                color: accent && hover ? Color.accentColor.opacity(0.55) : .clear,
                radius: 12, y: 4
            )
            .scaleEffect(hover ? 1.04 : 1.0)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: Anim.normal), value: hover)
    }
}
