import SwiftUI

/// Top navigation tab
enum NavigationTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case explore = "Explore"
    case popular = "Popular"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "safari.fill"
        case .popular: return "flame.fill"
        }
    }
}

/// Netflix-style transparent floating header that overlays content
struct TopNavigationBar: View {
    @Binding var selectedTab: NavigationTab
    @Binding var searchText: String
    @Binding var isImporting: Bool
    @State private var isSearching = false

    /// When true, header has solid background (for scrolled state)
    var isScrolled: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Logo
            Text("W")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.red, .red.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .padding(.trailing, 28)

            // Navigation tabs - Netflix style inline text
            HStack(spacing: 20) {
                ForEach(NavigationTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .bold : .regular))
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Right actions
            HStack(spacing: 16) {
                // Search
                if isSearching {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))

                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .frame(width: 160)

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                isSearching = false; searchText = ""
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { isSearching = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("f", modifiers: .command)
                }

                // Import
                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("i", modifiers: .command)

                // Settings
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(isScrolled ? 0.95 : 0.7), location: 0),
                    .init(color: .black.opacity(isScrolled ? 0.9 : 0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
