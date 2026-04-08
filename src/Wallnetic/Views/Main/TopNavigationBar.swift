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

/// Striking glass navigation bar with neon-glow tabs
struct TopNavigationBar: View {
    @Binding var selectedTab: NavigationTab
    @Binding var searchText: String
    @Binding var isImporting: Bool
    @State private var isSearching = false
    @State private var hoveredTab: NavigationTab?
    var isScrolled: Bool = false

    var body: some View {
        ZStack {
            // Left side - search
            HStack {
                if isSearching {
                    searchBar
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                } else {
                    Button {
                        withAnimation(.easeOut(duration: Anim.normal)) { isSearching = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(6)
                            .background(Circle().fill(Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("f", modifiers: .command)
                }

                Spacer()
            }

            // Center - logo + tabs
            HStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
                    .shadow(color: .accentColor.opacity(0.3), radius: 6)

                HStack(spacing: 2) {
                    ForEach(NavigationTab.allCases) { tab in
                        tabButton(tab)
                    }
                }
            }

            // Right side - import + settings
            HStack(spacing: 12) {
                Spacer()

                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("i", modifiers: .command)

                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            ZStack {
                // Glass effect
                Color.black.opacity(isScrolled ? 0.85 : 0.4)
                if isScrolled {
                    Color.white.opacity(0.03)
                }
            }
            .animation(.easeInOut(duration: Anim.medium), value: isScrolled)
        )
        .overlay(alignment: .bottom) {
            // Subtle bottom glow line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .accentColor.opacity(isScrolled ? 0.15 : 0), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
        }
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
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 10))
                    .neonGlow(.accentColor, isActive: isSelected, radius: 6)

                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(isHovered ? 0.8 : 0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.2))
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                    } else if isHovered {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    }
                }
            )
            .neonGlow(.accentColor, isActive: isSelected, radius: 10)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: Anim.micro)) { hoveredTab = h ? tab : nil }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.accentColor.opacity(0.7))

            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 160)

            Button {
                withAnimation(.easeOut(duration: Anim.fast)) {
                    isSearching = false; searchText = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassBackground(cornerRadius: 8, opacity: 0.08)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
        )
    }
}
