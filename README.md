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

**Wallpaper Engine** has 40M+ users on Windows &mdash; now Mac users finally have a native alternative built with SwiftUI and Metal.

---

## Features

### Live Video Wallpapers
- Play any video file (MP4, MOV, M4V) as your desktop background
- Seamless looping with zero stuttering
- Drag & drop or file picker import

### Multi-Monitor Support
- Set different wallpapers for each display
- Same wallpaper across all monitors option
- Automatic display detection and hot-plug support

### Notification Center Widget
- Glassmorphism clock widget with wallpaper background
- Real-time clock and date display (updates every minute)
- Play/pause and next wallpaper controls
- Favorites quick-switch thumbnails
- Available in Small, Medium, and Large sizes

### Smart Power Management
- Auto-pause on battery power
- Pause when fullscreen apps are active
- Automatic resume when conditions change
- Configurable per preference

### Optimized Performance
- **Metal GPU acceleration** for smooth playback
- Minimal CPU usage (~2-5%)
- Memory-efficient thumbnail caching
- Runs silently in the background

### Native macOS Experience
- Built entirely with SwiftUI
- Dark, Light, and System theme support
- Menu bar controls with favorites quick-switch
- Launch at login
- Keyboard shortcuts throughout

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
| RAM | 4 GB minimum |
| Storage | 50 MB + your video files |

### Mac App Store

Coming soon.

### Download from Releases

| Platform | Download |
|----------|----------|
| macOS (Universal) | [Latest Release](https://github.com/fatihkan/wallnetic/releases/latest) |

### Build from Source

```bash
# Clone the repository
git clone https://github.com/fatihkan/wallnetic.git
cd wallnetic/src/Wallnetic

# Install XcodeGen (if not installed)
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
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
| Project Gen | XcodeGen |

---

## Project Structure

```
wallnetic/
├── src/
│   ├── Wallnetic/              # Main app target
│   │   ├── App/                # Entry point, AppDelegate
│   │   ├── Engine/             # Video rendering, desktop windows, power mgmt
│   │   ├── Models/             # Wallpaper, Collection, AI models
│   │   ├── Views/              # SwiftUI views
│   │   ├── Services/           # WallpaperManager, Collections, Thumbnails
│   │   ├── Resources/          # Info.plist, Entitlements, Assets
│   │   └── project.yml         # XcodeGen config
│   └── WallneticWidget/        # Widget extension
│       ├── Views/              # Small, Medium, Large widget views
│       ├── Provider/           # Timeline provider
│       └── Models/             # Shared data models
├── docs/                       # Documentation, privacy policy
└── README.md
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd + I` | Import videos |
| `Cmd + P` | Toggle play/pause |
| `Cmd + O` | Open main window |
| `Cmd + ,` | Settings |
| `Cmd + Q` | Quit |

---

## Roadmap

### v1.0 &mdash; Live Wallpapers
- [x] Video playback engine with seamless looping
- [x] Multi-monitor support with per-display assignment
- [x] Library management with collections and favorites
- [x] Smart power management (battery, fullscreen detection)
- [x] Metal GPU rendering
- [x] Notification Center widget with glassmorphism clock
- [x] Menu bar controls
- [x] Dark/Light/System themes

### v1.1 &mdash; Planned
- [ ] Wallpaper effects (blur, brightness, tint)
- [ ] Time-of-day auto wallpaper switch
- [ ] Apple Shortcuts integration
- [ ] Video trimming

### v2.0 &mdash; AI Integration
- [ ] AI video generation from text prompts
- [ ] Image-to-video animation
- [ ] Multiple AI models
- [ ] Generation history

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

- Website: [wallnetic.app](https://wallnetic.app)
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
