import SwiftUI
import UniformTypeIdentifiers

struct AIGenerateView: View {
    @State private var selectedImage: NSImage?
    @State private var selectedImageURL: URL?
    @State private var isImporting = false
    @State private var isDragging = false
    @State private var errorMessage: String?
    @State private var isValidImage = false

    // Supported image types
    private let supportedTypes: [UTType] = [.jpeg, .png, .heic, .heif, .tiff]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main content
            if let image = selectedImage {
                imagePreviewView(image)
            } else {
                dropZoneView
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
                Text("AI Generate")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Upload an image to generate AI wallpapers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if selectedImage != nil {
                Button("Clear") {
                    clearSelection()
                }
            }
        }
        .padding()
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
                    )

                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(isDragging ? .accentColor : .secondary)

                    VStack(spacing: 8) {
                        Text("Drop an image here")
                            .font(.headline)
                            .foregroundColor(isDragging ? .accentColor : .primary)

                        Text("or")
                            .foregroundColor(.secondary)

                        Button("Choose File") {
                            isImporting = true
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Text("Supports JPEG, PNG, HEIC")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 400, maxHeight: 300)
            .onDrop(of: [.image, .fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
                return true
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Image Preview

    private func imagePreviewView(_ image: NSImage) -> some View {
        VStack(spacing: 20) {
            // Image preview
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.05))

                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
                    .padding()
            }
            .frame(maxWidth: 500, maxHeight: 350)
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)

            // Image info
            if let url = selectedImageURL {
                VStack(spacing: 8) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 16) {
                        Label("\(Int(image.size.width)) × \(Int(image.size.height))", systemImage: "aspectratio")
                        Label(formatFileSize(url), systemImage: "doc")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            // Validation status
            if isValidImage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Image ready for AI generation")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }

            // Action buttons
            HStack(spacing: 16) {
                Button("Choose Different Image") {
                    isImporting = true
                }
                .buttonStyle(.bordered)

                Button("Continue to Style Selection") {
                    // TODO: Navigate to style selection (#37)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidImage)
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Image Handling

    private func handleImageImport(_ result: Result<[URL], Error>) {
        errorMessage = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadImage(from: url)

        case .failure(let error):
            errorMessage = "Failed to open file: \(error.localizedDescription)"
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        errorMessage = nil

        guard let provider = providers.first else { return }

        // Try loading as image first
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { image, error in
                DispatchQueue.main.async {
                    if let nsImage = image as? NSImage {
                        self.selectedImage = nsImage
                        self.selectedImageURL = nil
                        self.validateImage(nsImage)
                    } else if let error = error {
                        self.errorMessage = "Failed to load image: \(error.localizedDescription)"
                    }
                }
            }
            return
        }

        // Try loading as file URL
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            DispatchQueue.main.async {
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    self.errorMessage = "Invalid file"
                    return
                }
                self.loadImage(from: url)
            }
        }
    }

    private func loadImage(from url: URL) {
        // Check if URL is accessible
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Validate file type
        guard let typeIdentifier = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
              let utType = UTType(typeIdentifier),
              supportedTypes.contains(where: { utType.conforms(to: $0) }) else {
            errorMessage = "Unsupported file format. Please use JPEG, PNG, or HEIC."
            return
        }

        // Load image
        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "Failed to load image from file"
            return
        }

        selectedImage = image
        selectedImageURL = url
        validateImage(image)
    }

    private func validateImage(_ image: NSImage) {
        // Check minimum dimensions (at least 512x512 for good AI results)
        let minDimension: CGFloat = 512
        let width = image.size.width
        let height = image.size.height

        if width < minDimension || height < minDimension {
            errorMessage = "Image too small. Minimum size is \(Int(minDimension))×\(Int(minDimension)) pixels."
            isValidImage = false
            return
        }

        // Check maximum dimensions (limit for API)
        let maxDimension: CGFloat = 8192
        if width > maxDimension || height > maxDimension {
            errorMessage = "Image too large. Maximum size is \(Int(maxDimension))×\(Int(maxDimension)) pixels."
            isValidImage = false
            return
        }

        isValidImage = true
        errorMessage = nil
    }

    private func clearSelection() {
        selectedImage = nil
        selectedImageURL = nil
        isValidImage = false
        errorMessage = nil
    }

    private func formatFileSize(_ url: URL) -> String {
        guard let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resources.fileSize else {
            return "Unknown size"
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }
}

#Preview {
    AIGenerateView()
        .frame(width: 600, height: 500)
}
