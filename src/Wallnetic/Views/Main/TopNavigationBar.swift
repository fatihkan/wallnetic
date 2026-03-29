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

/// Netflix-style centered navigation bar with app icon
struct TopNavigationBar: View {
    @Binding var selectedTab: NavigationTab
    @Binding var searchText: String
    @Binding var isImporting: Bool
    @State private var isSearching = false
    var isScrolled: Bool = false

    var body: some View {
        ZStack {
            // Left side - search
            HStack {
                if isSearching {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))

                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .frame(width: 140)

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                isSearching = false; searchText = ""
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { isSearching = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("f", modifiers: .command)
                }

                Spacer()
            }

            // Center - logo + tabs
            HStack(spacing: 20) {
                // App icon from assets
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)

                // Navigation tabs
                HStack(spacing: 4) {
                    ForEach(NavigationTab.allCases) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .bold : .regular))
                                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    selectedTab == tab
                                    ? Capsule().fill(Color.white.opacity(0.12))
                                    : nil
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Right side - import + settings
            HStack(spacing: 14) {
                Spacer()

                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
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
            Color.black.opacity(isScrolled ? 0.92 : 0.5)
                .animation(.easeInOut(duration: 0.3), value: isScrolled)
        )
    }
}
