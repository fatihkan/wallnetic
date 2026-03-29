# Wallnetic

> **Live Video Wallpaper Engine for macOS**

[![macOS](https://img.shields.io/badge/macOS-13.0+-black.svg?style=flat&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138.svg?style=flat&logo=swift&logoColor=white)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-blue.svg?style=flat&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Metal](https://img.shields.io/badge/Metal-GPU-8E8E93.svg?style=flat&logo=apple)](https://developer.apple.com/metal/)
[![CI](https://img.shields.io/github/actions/workflow/status/fatihkan/wallnetic/ci.yml?branch=main&label=CI)](https://github.com/fatihkan/wallnetic/actions)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.1.0-blue.svg)](https://github.com/fatihkan/wallnetic/releases/tag/v1.1.0)

<p align="center">
  <video src="https://github.com/user-attachments/assets/fdb62e04-455d-43e5-8b8f-6dbee796dc90" width="800" autoplay loop muted playsinline>
  </video>
</p>

## What is Wallnetic?

Wallnetic brings **live video wallpapers** to your Mac desktop. Transform your workspace with dynamic, animated backgrounds that run efficiently in the background.

**Wallpaper Engine** has 40M+ users on Windows &mdash; now Mac users finally have a native alternative built with SwiftUI and Metal.

---

## Features

### Netflix-Style Interface
- Home, Explore, Popular, and Discover tabs
- Full-screen hero banner with auto-rotating showcase
- Horizontal carousel sections with hover previews
- Dark theme optimized for media browsing

### Discover Wallpaper Sources
- Browse 6 wallpaper sources: Pixabay, Pexels, MyLiveWallpapers, DesktopHut, MoeWalls, MotionBGs
- In-app browser with automatic video download detection
- Scan any page to find and download all videos
- Progress tracking with auto-import to library

### Live Video Wallpapers
- Play any video file (MP4, MOV, M4V, GIF, WebM) as your desktop background
- Seamless looping with zero stuttering
- Drag & drop or file picker import
- Crossfade transitions between wallpaper changes

### Per-Space Wallpapers
- Set different wallpapers for each macOS Space (virtual desktop)
- Auto-switches when changing Spaces via Mission Control
- Right-click any wallpaper > "Set for This Space"

### Lock Screen Video
- Video wallpaper on lock screen with clock overlay
- Uses current wallpaper or a specific selection
- Auto-detects screen lock/unlock

### Multi-Monitor Support
- Set different wallpapers for each display
- Same wallpaper across all monitors option
- Automatic display detection and hot-plug support

### Wallpaper Effects
- Brightness, contrast, saturation, blur, tint, and vignette
- 8 presets: None, Dim, Vivid, Moody, Film, B&W, Dreamy, Focus
- Real-time CIFilter effects on video layer

### Time-of-Day Auto Switch
- 4 time slots: Morning, Afternoon, Evening, Night
- Assign wallpapers per slot with configurable hours

### Notification Center Widget
- Glassmorphism clock widget with wallpaper background
- Play/pause and next wallpaper controls
- Favorites quick-switch thumbnails
- Small, Medium, and Large sizes

### Smart Power Management
- Auto-pause on battery power
- Pause when fullscreen apps are active
- Automatic resume when conditions change

### Apple Shortcuts & Siri
- Set Wallpaper, Next Wallpaper, Toggle Playback, Random Wallpaper
- Siri: "Change wallpaper in Wallnetic"
- macOS 14+ required

### Performance
- **Metal GPU acceleration** for smooth playback
- 3 performance modes: Quality, Balanced, Battery Saver
- Minimal CPU usage (~2-5%)
- Async image caching

---

## Installation

### Requirements

| Component | Requirement |
|-----------|-------------|
| macOS | 13.0 (Ventura) or later |
| Processor | Apple Silicon (M1/M2/M3/M4) or Intel |
| RAM | 4 GB minimum |
| Storage | 50 MB + your video files |

### Download

| Platform | Download |
|----------|----------|
| macOS (Apple Silicon) | [Wallnetic_1.1.0_arm64.dmg](https://github.com/fatihkan/wallnetic/releases/latest) |
| macOS (Intel) | [Wallnetic_1.1.0_x86_64.dmg](https://github.com/fatihkan/wallnetic/releases/latest) |

### Build from Source

```bash
git clone https://github.com/fatihkan/wallnetic.git
cd wallnetic/src/Wallnetic
brew install xcodegen
xcodegen generate
open Wallnetic.xcodeproj
# Build and run (Cmd + R)
```

> Requires Xcode 15.0+ and macOS 13.0+

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 5.9 |
| UI | SwiftUI |
| Video Engine | AVFoundation + AVPlayerLooper |
| GPU Rendering | Metal |
| Architecture | MVVM + Services |
| Widget | WidgetKit |
| In-App Purchase | StoreKit 2 |
| Project Gen | XcodeGen |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd + I` | Import videos |
| `Cmd + P` | Toggle play/pause |
| `Cmd + N` | Next wallpaper |
| `Cmd + F` | Search |
| `Cmd + O` | Open main window |
| `Cmd + ,` | Settings |

---

## Roadmap

### v1.0 &mdash; Core
- [x] Video playback engine with seamless looping
- [x] Multi-monitor support
- [x] Library management with collections and favorites
- [x] Smart power management
- [x] Metal GPU rendering
- [x] Notification Center widget
- [x] Menu bar controls

### v1.1 &mdash; Current
- [x] Netflix-style UI redesign
- [x] Discover wallpaper sources (Pixabay, Pexels, web browser)
- [x] Per-Space wallpapers
- [x] Lock screen video
- [x] Wallpaper effects (blur, brightness, tint, vignette)
- [x] Time-of-day auto switch
- [x] Apple Shortcuts & Siri integration
- [x] GIF/WebM/WebP format support
- [x] Crossfade transitions
- [x] Performance modes

### v2.0 &mdash; Planned
- [ ] AI video generation from text prompts
- [ ] Wallpaper marketplace
- [ ] Music reactive mode
- [ ] iCloud library sync

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## Support the Project

If you find Wallnetic useful, consider supporting its development:

<a href="https://buymeacoffee.com/fatihkan" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="50">
</a>

---

## Author

**Fatih Kan**

- Website: [github.com/fatihkan/wallnetic](https://github.com/fatihkan/wallnetic)
- GitHub: [@fatihkan](https://github.com/fatihkan)
- Twitter: [@KanFatih](https://twitter.com/KanFatih)

---

## License

This project is licensed under the MIT License &mdash; see the [LICENSE](LICENSE) file for details.

## Privacy

Wallnetic does not collect any personal data. All wallpapers are stored locally on your Mac. See [PRIVACY.md](PRIVACY.md) for details.

---

<p align="center">
  Made with care for Mac users who deserve better wallpapers.
</p>
