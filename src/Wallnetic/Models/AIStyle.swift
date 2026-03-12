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

    static let noir = AIStyle(
        id: "noir",
        name: "Noir",
        description: "Dark, moody film noir atmosphere",
        icon: "theatermasks.fill",
        prompt: "film noir style, dramatic shadows, high contrast, black and white, moody atmosphere, cinematic, mysterious, rainy streets",
        negativePrompt: "colorful, bright, cheerful, cartoon",
        color: Color(red: 0.2, green: 0.2, blue: 0.2)
    )

    static let steampunk = AIStyle(
        id: "steampunk",
        name: "Steampunk",
        description: "Victorian era meets mechanical fantasy",
        icon: "gearshape.2.fill",
        prompt: "steampunk aesthetic, victorian era, brass gears, copper pipes, steam machinery, clockwork mechanisms, industrial revolution, ornate details",
        negativePrompt: "modern, digital, minimalist, nature",
        color: Color(red: 0.7, green: 0.5, blue: 0.3)
    )

    static let tropical = AIStyle(
        id: "tropical",
        name: "Tropical",
        description: "Paradise beaches and ocean views",
        icon: "beach.umbrella.fill",
        prompt: "tropical paradise, pristine beach, crystal clear water, palm trees, turquoise ocean, white sand, sunset, maldives style, travel photography",
        negativePrompt: "urban, cold, winter, snow",
        color: Color(red: 0.0, green: 0.8, blue: 0.8)
    )

    static let gothic = AIStyle(
        id: "gothic",
        name: "Gothic",
        description: "Dark medieval architecture",
        icon: "building.columns.fill",
        prompt: "gothic architecture, dark cathedral, medieval castle, dramatic lighting, mysterious atmosphere, gargoyles, stained glass, moonlit night",
        negativePrompt: "modern, bright, cheerful, minimalist",
        color: Color(red: 0.3, green: 0.1, blue: 0.3)
    )

    static let ukiyoe = AIStyle(
        id: "ukiyoe",
        name: "Ukiyo-e",
        description: "Traditional Japanese woodblock art",
        icon: "mountain.2.fill",
        prompt: "ukiyo-e style, japanese woodblock print, traditional japanese art, hokusai inspired, waves, mount fuji, cherry blossoms, elegant composition",
        negativePrompt: "photorealistic, modern, western, 3d render",
        color: Color(red: 0.8, green: 0.2, blue: 0.2)
    )

    static let neon = AIStyle(
        id: "neon",
        name: "Neon",
        description: "Vibrant neon glow effects",
        icon: "lightbulb.fill",
        prompt: "neon lights, glowing colors, dark background, vibrant pink blue purple, electric atmosphere, night scene, light trails, synthwave",
        negativePrompt: "daylight, natural, muted colors, vintage",
        color: Color(red: 1.0, green: 0.0, blue: 0.5)
    )

    static let vintage = AIStyle(
        id: "vintage",
        name: "Vintage",
        description: "Nostalgic retro photography",
        icon: "camera.aperture",
        prompt: "vintage photography, retro aesthetic, film grain, faded colors, 1970s style, nostalgic, polaroid look, warm tones, analog feel",
        negativePrompt: "modern, digital, sharp, vibrant",
        color: Color(red: 0.8, green: 0.7, blue: 0.5)
    )

    static let surreal = AIStyle(
        id: "surreal",
        name: "Surreal",
        description: "Dreamlike surrealist art",
        icon: "eye.fill",
        prompt: "surrealist art, salvador dali inspired, dreamlike scene, impossible architecture, melting objects, floating elements, subconscious imagery, artistic masterpiece",
        negativePrompt: "realistic, ordinary, simple, minimalist",
        color: Color(red: 0.6, green: 0.3, blue: 0.6)
    )

    static let geometric = AIStyle(
        id: "geometric",
        name: "Geometric",
        description: "Bold geometric patterns",
        icon: "triangle.fill",
        prompt: "geometric art, bold shapes, triangles, hexagons, symmetrical patterns, modern design, colorful gradients, mathematical precision, isometric",
        negativePrompt: "organic, natural, realistic, photographic",
        color: Color(red: 0.9, green: 0.3, blue: 0.3)
    )

    static let aurora = AIStyle(
        id: "aurora",
        name: "Aurora",
        description: "Northern lights and night skies",
        icon: "sparkle",
        prompt: "aurora borealis, northern lights, night sky, stars, green and purple lights, arctic landscape, snowy mountains, magical atmosphere, long exposure",
        negativePrompt: "daylight, urban, buildings, people",
        color: Color(red: 0.2, green: 0.8, blue: 0.5)
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
        .space,
        .noir,
        .steampunk,
        .tropical,
        .gothic,
        .ukiyoe,
        .neon,
        .vintage,
        .surreal,
        .geometric,
        .aurora
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
