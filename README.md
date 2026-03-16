# Wallnetic

> **Live Video Wallpaper Engine for macOS**

[![macOS](https://img.shields.io/badge/macOS-13.0+-black.svg?style=flat&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138.svg?style=flat&logo=swift&logoColor=white)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-blue.svg?style=flat&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Metal](https://img.shields.io/badge/Metal-GPU-8E8E93.svg?style=flat&logo=apple)](https://developer.apple.com/metal/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.0.0-blue.svg)](https://github.com/fatihkan/wallnetic/releases/tag/v1.0.0)

<p align="center">
  <video src="https://github.com/user-attachments/assets/fdb62e04-455d-43e5-8b8f-6dbee796dc90" width="800" autoplay loop muted playsinline>
  </video>
</p>

## What is Wallnetic?

Wallnetic brings **live video wallpapers** to your Mac desktop. Transform your workspace with dynamic, animated backgrounds that run efficiently in the background.

**Wallpaper Engine** has 40M+ users on Windows - now Mac users finally have a native alternative!

---

## Features

### Live Video Wallpapers
- Play any video file (MP4, MOV, M4V) as your desktop background
- Smooth looping with no stuttering
- Drag & drop video import

### Library Management
- Organize wallpapers in custom collections
- Mark favorites for quick access
- Search and filter your library
- Recently added section

### Multi-Monitor Support
- Set different wallpapers for each display
- Same wallpaper across all monitors option
- Automatic screen detection
- Per-display control

### Smart Power Management
- Auto-pause when on battery power
- Pause when fullscreen apps are active
- Resume automatically when conditions change

### Optimized Performance
- **Metal GPU acceleration** for smooth playback
- Minimal CPU usage (~2-5%)
- Memory-efficient design
- Runs silently in the background

### Native macOS Experience
- Built with SwiftUI
- Dark, Light, and System theme support
- Menu bar app for quick access
- Launch at login option

---

## Screenshots

<p align="center">
  <img src="docs/assets/screenshot-main.png" alt="Main Window" width="600"/>
</p>

<p align="center">
  <img src="docs/assets/screenshot-settings.png" alt="Settings" width="500"/>
</p>

---

## Installation

### Requirements

| Component | Requirement |
|-----------|-------------|
| macOS | 13.0 (Ventura) or later |
| Processor | Apple Silicon (M1/M2/M3/M4) or Intel |
| RAM | 4GB minimum |
| Storage | 50MB + your video files |

### Download

| Platform | Architecture | Download |
|----------|--------------|----------|
| macOS | Apple Silicon (M1/M2/M3/M4) | [Download DMG](https://github.com/fatihkan/wallnetic/releases/latest) |
| macOS | Intel | [Download DMG](https://github.com/fatihkan/wallnetic/releases/latest) |
| App Store | Universal | Coming Soon |

> **Latest Version:** Check [Releases](https://github.com/fatihkan/wallnetic/releases) for the latest version

### macOS Installation

1. **Download** the DMG file for your Mac (Apple Silicon or Intel)

2. **Open** the DMG and drag Wallnetic to Applications folder

3. **First Launch** - Since the app is not signed with an Apple Developer certificate, you'll need to bypass Gatekeeper:

   **Option A: Right-click method**
   ```
   Right-click on Wallnetic.app → Click "Open" → Click "Open" again in the dialog
   ```

   **Option B: Terminal method**
   ```bash
   xattr -cr /Applications/Wallnetic.app
   ```

   **Option C: System Settings**
   ```
   System Settings → Privacy & Security → Scroll down → Click "Open Anyway"
   ```

4. **Grant Permissions** - When prompted, allow:
   - Screen Recording (required for desktop wallpaper)
   - Accessibility (optional, for keyboard shortcuts)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/fatihkan/wallnetic.git
cd wallnetic

# Open in Xcode
open src/Wallnetic/Wallnetic.xcodeproj

# Build and run (⌘ + R)
```

> **Note:** Building from source requires Xcode 15.0+ and macOS 13.0+

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI |
| Video Engine | AVFoundation |
| GPU Rendering | Metal |
| Architecture | MVVM |

---

## Roadmap

### Phase 1: MVP - Live Wallpapers ✅
- [x] Video playback engine
- [x] Multi-monitor support
- [x] Library with collections & favorites
- [x] Power management
- [x] Metal rendering
- [x] Theme support (Dark/Light/System)
- [x] App Store submission

### Phase 2: AI Integration (Coming Soon)
- [ ] AI video generation from text prompts
- [ ] Image-to-video animation
- [ ] Multiple AI models (Kling, Minimax, Luma, etc.)
- [ ] Scheduled daily generation

### Phase 3: Effects & More
- [ ] Particle effects
- [ ] Audio-reactive animations
- [ ] Wallpaper marketplace

See [ROADMAP.md](docs/ROADMAP.md) for the full development plan.

---

## Project Structure

```
wallnetic/
├── src/Wallnetic/           # Xcode project
│   ├── App/                 # App entry & delegate
│   ├── Engine/              # Video rendering engine
│   │   ├── VideoRenderer.swift
│   │   ├── MetalVideoRenderer.swift
│   │   ├── DesktopWindowController.swift
│   │   └── PowerManager.swift
│   ├── Views/               # SwiftUI views
│   ├── Services/            # Business logic
│   └── Models/              # Data models
├── docs/                    # Documentation
├── PRIVACY.md               # Privacy Policy
└── README.md
```

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## Support

If you find this project useful, consider supporting its development:

<a href="https://buymeacoffee.com/fatihkan" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="50">
</a>

---

## Author

**Fatih Kan**

- Twitter: [@pariloapp](https://twitter.com/pariloapp)
- GitHub: [@fatihkan](https://github.com/fatihkan)
- LinkedIn: [Fatih Kan](https://linkedin.com/in/fatihkan)

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Privacy

Wallnetic does not collect any user data. See [PRIVACY.md](PRIVACY.md) for details.

---

<p align="center">
  Made with ❤️ for Mac users who deserve better wallpapers
</p>
