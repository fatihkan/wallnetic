import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, description: String, colors: [Color])] = [
        ("photo.on.rectangle.angled", "Welcome to Wallnetic",
         "Transform your desktop with stunning live video wallpapers.",
         [.purple, .blue]),
        ("plus.circle.fill", "Import Your Videos",
         "Drag and drop video files or use the import button to add wallpapers to your library.",
         [.blue, .cyan]),
        ("wand.and.stars", "AI Video Generation",
         "Create unique wallpapers with AI. Choose from 7 models and 18 artistic styles.",
         [.pink, .purple]),
        ("display.2", "Multi-Monitor Support",
         "Set different wallpapers for each display. Wallnetic automatically detects all connected monitors.",
         [.green, .teal])
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            TabView(selection: $currentStep) {
                ForEach(0..<steps.count, id: \.self) { index in
                    stepView(steps[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: 320)

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == currentStep ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3), value: currentStep)
                }
            }
            .padding(.vertical, 16)

            // Buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation(.spring(response: 0.4)) { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Get Started") {
                        withAnimation { isPresented = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 440)
    }

    private func stepView(_ step: (icon: String, title: String, description: String, colors: [Color])) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: step.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 100, height: 100)
                    .opacity(0.15)

                Image(systemName: step.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(colors: step.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            Text(step.title)
                .font(.title2)
                .fontWeight(.bold)

            Text(step.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
