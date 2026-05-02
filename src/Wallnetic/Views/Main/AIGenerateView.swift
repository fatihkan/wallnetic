import SwiftUI
import UniformTypeIdentifiers

struct AIGenerateView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @StateObject private var vm = AIGenerateViewModel()
    @AppStorage("selectedVideoModel") private var selectedModelRaw: String = VideoModel.klingStandard.rawValue

    // UI-only state (file picker / drag-hover / image preview)
    @State private var selectedImage: NSImage?
    @State private var selectedImageURL: URL?
    @State private var isImporting = false
    @State private var isDragging = false
    @State private var isValidImage = false

    // Prompt state — view-local because the input field binds to it directly.
    @State private var prompt: String = ""
    @State private var selectedDuration: Int = 5
    @State private var selectedAspectRatio: String = "16:9"

    private var selectedModel: VideoModel {
        VideoModel(rawValue: selectedModelRaw) ?? .klingStandard
    }

    // Supported image types for image-to-video
    private let supportedTypes: [UTType] = [.jpeg, .png, .heic, .heif, .tiff]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main content
            if vm.isGenerating {
                generationProgressView
            } else if let videoURL = vm.generatedVideoURL {
                generatedVideoView(videoURL)
            } else if vm.errorMessage != nil {
                errorView
            } else {
                promptInputView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImageImport(result)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Video Generator")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Create anime & loop videos with AI")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Model selector
            Menu {
                ForEach(VideoModel.allCases, id: \.self) { model in
                    Button {
                        selectedModelRaw = model.rawValue
                    } label: {
                        HStack {
                            if model == selectedModel {
                                Image(systemName: "checkmark")
                            }
                            Text(model.displayName)
                            if model.isAnimeOptimized {
                                Text("🎨")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: selectedModel.icon)
                    Text(selectedModel.displayName)
                    Image(systemName: "chevron.down")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }

    // MARK: - Prompt Input View

    private var promptInputView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Optional source image
                sourceImageSection

                // Prompt input
                promptSection

                // Settings
                settingsSection

                // Generate button
                generateButton
            }
            .padding()
        }
    }

    private var sourceImageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Source Image")
                    .font(.headline)
                Text("(Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let image = selectedImage {
                HStack(spacing: 16) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 120, maxHeight: 80)
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        if let url = selectedImageURL {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                        }
                        Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isValidImage {
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    Spacer()

                    Button("Remove") {
                        clearImage()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [6])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
                        )

                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundColor(.secondary)

                        Text("Drop image or")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Choose File") {
                            isImporting = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding()
                }
                .frame(height: 120)
                .onDrop(of: [.image, .fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers)
                    return true
                }
            }

            Text("Add an image to animate it into a video, or leave empty for text-to-video")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt")
                .font(.headline)

            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            // Prompt suggestions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(promptSuggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            prompt = suggestion
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var promptSuggestions: [String] {
        if selectedModel.isAnimeOptimized {
            return [
                "Anime girl with flowing hair in the wind, cherry blossoms falling",
                "Cyberpunk city at night with neon lights, rain falling",
                "Magical forest with glowing fireflies, anime style",
                "Ocean waves under moonlight, peaceful loop animation",
                "Cozy lo-fi room with rain on window, warm lighting"
            ]
        } else {
            return [
                "Cinematic landscape with moving clouds, golden hour",
                "Abstract flowing particles, vibrant colors",
                "Underwater scene with rays of light",
                "Northern lights dancing over mountains",
                "Fireplace with flickering flames, cozy atmosphere"
            ]
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            HStack(spacing: 24) {
                // Duration
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Duration", selection: $selectedDuration) {
                        Text("5 sec").tag(5)
                        if selectedModel.maxDuration >= 10 {
                            Text("10 sec").tag(10)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                // Aspect Ratio
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aspect Ratio")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Aspect Ratio", selection: $selectedAspectRatio) {
                        ForEach(selectedModel.supportedAspectRatios, id: \.self) { ratio in
                            Text(ratio).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                Spacer()
            }

            // Cost estimate
            HStack {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(.secondary)
                Text("Estimated cost: $\(String(format: "%.2f", selectedModel.costPerSecond * Double(selectedDuration)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var generateButton: some View {
        VStack(spacing: 12) {
            Button {
                vm.startGeneration(
                    prompt: prompt,
                    model: selectedModel,
                    duration: selectedDuration,
                    aspectRatio: selectedAspectRatio,
                    sourceImage: selectedImage
                )
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Generate Video")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(prompt.isEmpty || !KeychainManager.shared.hasAPIKey(for: .falai))

            if !KeychainManager.shared.hasAPIKey(for: .falai) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Please add your fal.ai API key in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Generation Progress View

    private var generationProgressView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated icon
            if #available(macOS 14.0, *) {
                Image(systemName: "film.stack")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse)
            } else {
                Image(systemName: "film.stack")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 8) {
                Text("Generating Video...")
                    .font(.headline)

                Text(vm.generationStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Using \(selectedModel.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: vm.generationProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)

                HStack {
                    Text("\(Int(vm.generationProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)

                    Spacer()

                    if !vm.estimatedTimeRemaining.isEmpty {
                        Text(vm.estimatedTimeRemaining)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: 300)
            }

            Text("Video generation can take 1-3 minutes")
                .font(.caption)
                .foregroundColor(.secondary)

            // Cancel button
            Button(action: vm.cancelGeneration) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Cancel")
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Generated Video View

    private func generatedVideoView(_ videoURL: URL) -> some View {
        VStack(spacing: 20) {
            // Video preview (thumbnail for now)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)

                // Video player or thumbnail would go here
                VStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)

                    Text("Video Generated!")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(videoURL.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: 400, maxHeight: 250)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

            // Success message
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Video generation complete!")
                    .fontWeight(.medium)
            }

            // Action buttons
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        if vm.addToLibrary(videoURL, wallpaperManager: wallpaperManager) {
                            prompt = ""
                            clearImage()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Add to Library")
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([videoURL])
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text("Show in Finder")
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Button("Generate Another") {
                    vm.clearGeneratedVideo()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Generation Failed")
                    .font(.headline)

                Text(vm.errorMessage ?? "An unknown error occurred")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            HStack(spacing: 12) {
                Button("Try Again") {
                    vm.errorMessage = nil
                    vm.startGeneration(
                        prompt: prompt,
                        model: selectedModel,
                        duration: selectedDuration,
                        aspectRatio: selectedAspectRatio,
                        sourceImage: selectedImage
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("Start Over") {
                    vm.errorMessage = nil
                    clearImage()
                    prompt = ""
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Image Handling

    private func handleImageImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadImage(from: url)
        case .failure(let error):
            ErrorReporter.shared.report(error, context: "Failed to open image file")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { image, error in
                DispatchQueue.main.async {
                    if let nsImage = image as? NSImage {
                        self.selectedImage = nsImage
                        self.selectedImageURL = nil
                        self.validateImage(nsImage)
                    } else if let error = error {
                        ErrorReporter.shared.report(error, context: "Failed to load dropped image")
                    }
                }
            }
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            DispatchQueue.main.async {
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    ErrorReporter.shared.report(ImageError.invalidFile, context: "Drag and drop")
                    return
                }
                self.loadImage(from: url)
            }
        }
    }

    private func loadImage(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let typeIdentifier = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
              let utType = UTType(typeIdentifier),
              supportedTypes.contains(where: { utType.conforms(to: $0) }) else {
            ErrorReporter.shared.report(ImageError.unsupportedFormat, context: "Image import")
            return
        }

        guard let image = NSImage(contentsOf: url) else {
            ErrorReporter.shared.report(ImageError.loadFailed, context: "Image import")
            return
        }

        selectedImage = image
        selectedImageURL = url
        validateImage(image)
    }

    private func validateImage(_ image: NSImage) {
        let minDimension: CGFloat = 256
        if image.size.width < minDimension || image.size.height < minDimension {
            ErrorReporter.shared.report(ImageError.tooSmall(min: Int(minDimension)), context: "Image validation")
            isValidImage = false
            return
        }
        isValidImage = true
    }

    private func clearImage() {
        selectedImage = nil
        selectedImageURL = nil
        isValidImage = false
    }

    // Generation, cancellation, and library import live in
    // `AIGenerateViewModel` (#166).
}

// Image-import errors surfaced via `ErrorReporter`.
private enum ImageError: LocalizedError {
    case invalidFile
    case unsupportedFormat
    case loadFailed
    case tooSmall(min: Int)

    var errorDescription: String? {
        switch self {
        case .invalidFile:           return "Invalid file"
        case .unsupportedFormat:     return "Unsupported file format. Please use JPEG, PNG, or HEIC."
        case .loadFailed:            return "Failed to load image from file"
        case .tooSmall(let min):     return "Image too small. Minimum size is \(min)×\(min) pixels."
        }
    }
}

#Preview {
    AIGenerateView()
        .frame(width: 600, height: 600)
}
