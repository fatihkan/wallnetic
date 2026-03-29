import SwiftUI

/// Top navigation tab for the main content area
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

/// Netflix/Disney+ style top navigation bar
struct TopNavigationBar: View {
    @Binding var selectedTab: NavigationTab
    @Binding var searchText: String
    @Binding var isImporting: Bool
    @State private var isSearching = false

    var body: some View {
        HStack(spacing: 0) {
            // Logo
            HStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Wallnetic")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .padding(.trailing, 24)

            // Tab buttons
            HStack(spacing: 4) {
                ForEach(NavigationTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == tab
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.clear)
                        )
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Search
            HStack(spacing: 8) {
                if isSearching {
                    TextField("Search wallpapers...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    Button {
                        withAnimation { isSearching = false; searchText = "" }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { isSearching = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("f", modifiers: .command)
                }

                // Import
                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("i", modifiers: .command)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
