# Wallnetic

> AI-Powered Live Wallpaper Engine for macOS

[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Overview

Wallnetic is a native macOS application that brings **AI-powered live wallpapers** to your desktop. Unlike existing alternatives, Wallnetic lets you generate unique animated wallpapers from your own photos using AI.

### Why Wallnetic?

- **Wallpaper Engine** has 40M+ users on Windows but **doesn't exist on Mac**
- Existing Mac alternatives (Backdrop, WallMotion) **don't have AI integration**
- Mac users are willing to pay for premium customization tools

## Features (Planned)

### Phase 1 - MVP
- [ ] Play video files as live wallpaper
- [ ] Basic wallpaper controls (play/pause/change)
- [ ] Multi-monitor support
- [ ] Low CPU/GPU usage (Metal optimized)

### Phase 2 - AI Integration
- [ ] Generate static wallpapers from text prompts
- [ ] Transform your photos into artistic wallpapers
- [ ] Multiple AI style options (anime, realistic, abstract, etc.)
- [ ] Lock Screen support (macOS 14+)

### Phase 3 - Motion
- [ ] Generate animated wallpapers from static images
- [ ] AI video generation (photo → animation)
- [ ] Particle effects and ambient animations

### Phase 4 - Community
- [ ] Share wallpapers with other users
- [ ] Marketplace for premium content
- [ ] User-generated content platform

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI |
| Wallpaper Engine | ScreenSaver.framework |
| GPU Rendering | Metal |
| AI (Static) | Stable Diffusion API (Replicate/fal.ai) |
| AI (Video) | Pika / Runway API |
| Backend | Supabase |
| Payments | RevenueCat |

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- 4GB RAM minimum
- Internet connection for AI features

## Project Structure

```
wallnetic/
├── README.md
├── docs/
│   ├── ROADMAP.md          # Detailed development roadmap
│   ├── ARCHITECTURE.md     # Technical architecture
│   └── LEARNING_SWIFT.md   # Swift learning resources
├── .github/
│   └── ISSUE_TEMPLATE/     # GitHub issue templates
├── src/
│   └── Wallnetic/          # Xcode project
├── resources/
│   ├── design/             # UI/UX designs
│   └── assets/             # App assets
└── scripts/                # Build & utility scripts
```

## Development

### Prerequisites

1. Xcode 15.0+
2. macOS 13.0+
3. Apple Developer account (for distribution)

### Getting Started

```bash
# Clone the repository
git clone https://github.com/[username]/wallnetic.git
cd wallnetic

# Open in Xcode
open src/Wallnetic/Wallnetic.xcodeproj
```

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for the detailed development roadmap.

## Learning Resources

New to Swift? Check out [docs/LEARNING_SWIFT.md](docs/LEARNING_SWIFT.md) for a curated learning path.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

This project is currently in early development. Contributions welcome after MVP release.

---

**Status:** 🚧 In Development

**Target Launch:** App Store Q3 2026
