import SwiftUI

struct StyleSelectionView: View {
    let sourceImage: NSImage?
    @Binding var isPresented: Bool
    var onGenerate: ((AIStyle, String) -> Void)?

    @State private var selectedStyle: AIStyle?
    @State private var showCustomPrompt = false
    @State private var customPrompt = ""
    @State private var customNegativePrompt = ""
    @State private var additionalPrompt = ""

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Source image preview
                    sourceImageSection

                    // Style grid
                    styleGridSection

                    // Custom prompt section
                    customPromptSection
                }
                .padding()
            }

            Divider()

            // Footer with action buttons
            footerView
        }
        .frame(width: 600, height: 700)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Select Style")
                .font(.headline)

            Spacer()

            // Spacer for symmetry
            Text("Back")
                .opacity(0)
        }
        .padding()
    }

    // MARK: - Source Image Section

    @ViewBuilder
    private var sourceImageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sourceImage != nil ? "Source Image" : "Text-to-Image Generation")
                .font(.headline)

            HStack(spacing: 16) {
                if let image = sourceImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let style = selectedStyle {
                            HStack {
                                Image(systemName: style.icon)
                                    .foregroundColor(style.color)
                                Text(style.name)
                                    .fontWeight(.medium)
                            }
                        } else {
                            Text("No style selected")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Text-to-image mode
                    VStack(alignment: .leading, spacing: 8) {
                        let resolution = AIService.screenResolution
                        Text("Output: \(resolution.width) × \(resolution.height)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let style = selectedStyle {
                            HStack {
                                Image(systemName: style.icon)
                                    .foregroundColor(style.color)
                                Text(style.name)
                                    .fontWeight(.medium)
                            }
                        }

                        TextField("Describe your wallpaper...", text: $additionalPrompt)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
    }

    // MARK: - Style Grid

    private var styleGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a Style")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(AIStyle.allStyles) { style in
                    StyleCard(
                        style: style,
                        isSelected: selectedStyle?.id == style.id
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedStyle = style
                            showCustomPrompt = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Custom Prompt Section

    private var customPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Custom Prompt")
                    .font(.headline)

                Spacer()

                Toggle("", isOn: $showCustomPrompt)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if showCustomPrompt {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prompt")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextEditor(text: $customPrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 80)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Negative Prompt (optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextEditor(text: $customNegativePrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 60)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }

                    Text("Describe what you want to see. The AI will transform your image based on this prompt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                .onChange(of: customPrompt) { newValue in
                    if !newValue.isEmpty {
                        selectedStyle = .custom(prompt: newValue, negativePrompt: customNegativePrompt)
                    }
                }
                .onChange(of: customNegativePrompt) { newValue in
                    if !customPrompt.isEmpty {
                        selectedStyle = .custom(prompt: customPrompt, negativePrompt: newValue)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let style = selectedStyle {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected: \(style.name)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(style.prompt.prefix(60) + (style.prompt.count > 60 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Select a style to continue")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.escape)

            Button("Generate") {
                startGeneration()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedStyle == nil)
            .keyboardShortcut(.return)
        }
        .padding()
    }

    // MARK: - Actions

    private func startGeneration() {
        guard let style = selectedStyle else { return }

        // Build the final prompt
        var finalPrompt = additionalPrompt.isEmpty ? "" : additionalPrompt

        // Call the generate callback
        onGenerate?(style, finalPrompt)
        isPresented = false
    }
}

// MARK: - Style Card

struct StyleCard: View {
    let style: AIStyle
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Icon/Preview
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [style.color.opacity(0.3), style.color.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: style.icon)
                    .font(.system(size: 32))
                    .foregroundColor(style.color)
            }
            .frame(height: 80)

            // Name & Description
            VStack(spacing: 2) {
                Text(style.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(style.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? style.color : Color.clear, lineWidth: 3)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .shadow(color: isSelected ? style.color.opacity(0.3) : .clear, radius: 8)
    }
}

// MARK: - Preview

#Preview {
    StyleSelectionView(
        sourceImage: nil,
        isPresented: .constant(true)
    )
}
