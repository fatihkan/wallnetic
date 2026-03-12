import SwiftUI

/// AI generation style presets
struct AIStyle: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let prompt: String
    let negativePrompt: String
    let color: Color

    // MARK: - Preset Styles

    static let anime = AIStyle(
        id: "anime",
        name: "Anime",
        description: "Japanese animation style with vibrant colors",
        icon: "sparkles",
        prompt: "anime style, vibrant colors, detailed illustration, studio ghibli inspired, beautiful scenery, masterpiece quality",
        negativePrompt: "photorealistic, 3d render, blurry, low quality",
        color: .pink
    )

    static let realistic = AIStyle(
        id: "realistic",
        name: "Realistic",
        description: "Photorealistic high-quality imagery",
        icon: "camera.fill",
        prompt: "photorealistic, ultra high definition, 8k resolution, professional photography, stunning detail, cinematic lighting",
        negativePrompt: "cartoon, anime, illustration, painting, drawing",
        color: .blue
    )

    static let abstract = AIStyle(
        id: "abstract",
        name: "Abstract",
        description: "Artistic abstract patterns and shapes",
        icon: "scribble.variable",
        prompt: "abstract art, geometric patterns, flowing shapes, vibrant gradients, modern art, artistic composition",
        negativePrompt: "realistic, photographic, faces, text",
        color: .purple
    )

    static let cyberpunk = AIStyle(
        id: "cyberpunk",
        name: "Cyberpunk",
        description: "Futuristic neon-lit cityscapes",
        icon: "bolt.fill",
        prompt: "cyberpunk style, neon lights, futuristic city, rain-soaked streets, holographic displays, blade runner aesthetic, night scene",
        negativePrompt: "nature, daylight, vintage, historical",
        color: .cyan
    )

    static let fantasy = AIStyle(
        id: "fantasy",
        name: "Fantasy",
        description: "Magical worlds and ethereal scenes",
        icon: "wand.and.stars",
        prompt: "fantasy art, magical atmosphere, ethereal lighting, enchanted landscape, mystical scenery, dramatic sky, epic composition",
        negativePrompt: "modern, urban, technology, realistic",
        color: .indigo
    )

    static let minimalist = AIStyle(
        id: "minimalist",
        name: "Minimalist",
        description: "Clean, simple, elegant designs",
        icon: "square.on.circle",
        prompt: "minimalist design, clean lines, simple composition, elegant, modern aesthetic, subtle colors, sophisticated",
        negativePrompt: "cluttered, busy, complex, detailed",
        color: .gray
    )

    static let nature = AIStyle(
        id: "nature",
        name: "Nature",
        description: "Beautiful natural landscapes",
        icon: "leaf.fill",
        prompt: "nature landscape, breathtaking scenery, golden hour lighting, mountains, forests, lakes, national geographic quality",
        negativePrompt: "urban, buildings, people, cars",
        color: .green
    )

    static let vaporwave = AIStyle(
        id: "vaporwave",
        name: "Vaporwave",
        description: "Retro-futuristic aesthetic",
        icon: "sunset.fill",
        prompt: "vaporwave aesthetic, retro futurism, pink and blue gradients, 80s nostalgia, palm trees, sunset, greek statues, glitch art",
        negativePrompt: "realistic, modern, minimalist",
        color: Color(red: 1.0, green: 0.4, blue: 0.7)
    )

    static let watercolor = AIStyle(
        id: "watercolor",
        name: "Watercolor",
        description: "Soft watercolor painting style",
        icon: "paintbrush.fill",
        prompt: "watercolor painting, soft edges, flowing colors, artistic, delicate brush strokes, paper texture, beautiful composition",
        negativePrompt: "digital art, sharp edges, photorealistic",
        color: .orange
    )

    static let space = AIStyle(
        id: "space",
        name: "Space",
        description: "Cosmic scenes and galaxies",
        icon: "moon.stars.fill",
        prompt: "outer space, nebula, galaxies, stars, cosmic scene, universe, planets, astronomical, hubble telescope quality",
        negativePrompt: "earth, ground, people, buildings",
        color: Color(red: 0.2, green: 0.1, blue: 0.4)
    )

    // MARK: - All Styles

    static let allStyles: [AIStyle] = [
        .anime,
        .realistic,
        .abstract,
        .cyberpunk,
        .fantasy,
        .minimalist,
        .nature,
        .vaporwave,
        .watercolor,
        .space
    ]

    // MARK: - Custom Style

    static func custom(prompt: String, negativePrompt: String = "") -> AIStyle {
        AIStyle(
            id: "custom",
            name: "Custom",
            description: "Your custom style",
            icon: "pencil",
            prompt: prompt,
            negativePrompt: negativePrompt,
            color: .accentColor
        )
    }
}
