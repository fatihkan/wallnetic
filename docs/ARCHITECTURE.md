# Wallnetic Technical Architecture

> Teknik mimari ve sistem tasarımı

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         WALLNETIC ARCHITECTURE                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │                    macOS Application                          │  │
│   │  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐  │  │
│   │  │  SwiftUI   │  │  Menu Bar  │  │   Wallpaper Engine     │  │  │
│   │  │    App     │──│    App     │──│  (ScreenSaver.fw)      │  │  │
│   │  └────────────┘  └────────────┘  └────────────────────────┘  │  │
│   │        │              │                    │                  │  │
│   │        └──────────────┼────────────────────┘                  │  │
│   │                       │                                       │  │
│   │              ┌────────▼────────┐                              │  │
│   │              │   Core Engine   │                              │  │
│   │              │  (Video/Metal)  │                              │  │
│   │              └────────┬────────┘                              │  │
│   └───────────────────────┼──────────────────────────────────────┘  │
│                           │                                          │
│   ┌───────────────────────▼──────────────────────────────────────┐  │
│   │                      Backend Services                         │  │
│   │  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐  │  │
│   │  │  Supabase  │  │  AI APIs   │  │   RevenueCat          │  │  │
│   │  │  Auth/DB   │  │(Replicate) │  │   (Payments)          │  │  │
│   │  └────────────┘  └────────────┘  └────────────────────────┘  │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Application Layers

### 1. Presentation Layer (SwiftUI)

```
┌─────────────────────────────────────────┐
│            Presentation Layer            │
├─────────────────────────────────────────┤
│                                          │
│  Views/                                  │
│  ├── MainWindow/                         │
│  │   ├── ContentView.swift               │
│  │   ├── WallpaperGalleryView.swift      │
│  │   └── SettingsView.swift              │
│  ├── AIGeneration/                       │
│  │   ├── GenerateView.swift              │
│  │   ├── StyleSelectorView.swift         │
│  │   └── PromptInputView.swift           │
│  └── Components/                         │
│      ├── WallpaperCard.swift             │
│      ├── VideoPlayerView.swift           │
│      └── LoadingIndicator.swift          │
│                                          │
└─────────────────────────────────────────┘
```

### 2. Business Logic Layer

```
┌─────────────────────────────────────────┐
│          Business Logic Layer            │
├─────────────────────────────────────────┤
│                                          │
│  ViewModels/                             │
│  ├── MainViewModel.swift                 │
│  ├── GalleryViewModel.swift              │
│  ├── AIGenerationViewModel.swift         │
│  └── SettingsViewModel.swift             │
│                                          │
│  Services/                               │
│  ├── WallpaperService.swift              │
│  ├── AIService.swift                     │
│  ├── StorageService.swift                │
│  └── SubscriptionService.swift           │
│                                          │
└─────────────────────────────────────────┘
```

### 3. Core Engine Layer

```
┌─────────────────────────────────────────┐
│            Core Engine Layer             │
├─────────────────────────────────────────┤
│                                          │
│  Engine/                                 │
│  ├── WallpaperEngine.swift      # Ana    │
│  ├── VideoRenderer.swift        # Metal  │
│  ├── DisplayManager.swift       # Multi  │
│  └── PerformanceMonitor.swift   # CPU    │
│                                          │
│  Integrations/                           │
│  ├── ScreenSaverBridge.swift             │
│  ├── DesktopWindowController.swift       │
│  └── MenuBarController.swift             │
│                                          │
└─────────────────────────────────────────┘
```

### 4. Data Layer

```
┌─────────────────────────────────────────┐
│              Data Layer                  │
├─────────────────────────────────────────┤
│                                          │
│  Models/                                 │
│  ├── Wallpaper.swift                     │
│  ├── User.swift                          │
│  ├── GenerationRequest.swift             │
│  └── Subscription.swift                  │
│                                          │
│  Repositories/                           │
│  ├── WallpaperRepository.swift           │
│  ├── UserRepository.swift                │
│  └── LocalStorageRepository.swift        │
│                                          │
│  Network/                                │
│  ├── APIClient.swift                     │
│  ├── SupabaseClient.swift                │
│  └── AIAPIClient.swift                   │
│                                          │
└─────────────────────────────────────────┘
```

---

## Core Components

### Wallpaper Engine

macOS'ta live wallpaper uygulamanın yolu:

```swift
// Yaklaşım 1: Desktop Window Level
class DesktopWindowController: NSWindowController {
    func createDesktopWindow() {
        let window = NSWindow(
            contentRect: NSScreen.main!.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
        )
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

// Yaklaşım 2: ScreenSaver Framework
class WallpaperScreenSaverView: ScreenSaverView {
    override func draw(_ rect: NSRect) {
        // Video frame çiz
    }

    override func animateOneFrame() {
        // Her frame için çağrılır
    }
}
```

### Video Renderer (Metal)

```swift
import Metal
import AVFoundation

class VideoRenderer {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var videoPlayer: AVPlayer!

    func renderFrame(to texture: MTLTexture) {
        // Metal ile video frame render
    }
}
```

### Multi-Display Manager

```swift
class DisplayManager {
    func getAllDisplays() -> [NSScreen] {
        return NSScreen.screens
    }

    func setWallpaper(for screen: NSScreen, video: URL) {
        // Her ekran için ayrı wallpaper
    }

    func observeDisplayChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Ekran değişikliklerini handle et
        }
    }
}
```

---

## Backend Architecture

### Supabase Schema

```sql
-- Users table (Supabase Auth handles this)

-- Wallpapers table
CREATE TABLE wallpapers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id),
    title TEXT,
    type TEXT CHECK (type IN ('static', 'video', 'ai_generated')),
    file_url TEXT NOT NULL,
    thumbnail_url TEXT,
    ai_prompt TEXT,
    ai_style TEXT,
    is_public BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Generations table (AI üretim geçmişi)
CREATE TABLE generations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id),
    prompt TEXT,
    style TEXT,
    source_image_url TEXT,
    result_url TEXT,
    status TEXT CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    cost_credits INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Subscriptions (RevenueCat sync)
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id),
    plan TEXT,
    status TEXT,
    expires_at TIMESTAMPTZ,
    revenue_cat_id TEXT
);
```

### Edge Functions (AI Proxy)

```typescript
// supabase/functions/generate-image/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { prompt, style, imageUrl } = await req.json()

  // Rate limiting check
  // Credits check

  // Call Replicate/fal.ai
  const result = await fetch("https://api.replicate.com/v1/predictions", {
    method: "POST",
    headers: {
      "Authorization": `Token ${Deno.env.get("REPLICATE_API_KEY")}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      version: "stability-ai/sdxl",
      input: { prompt, style }
    })
  })

  return new Response(JSON.stringify(result), {
    headers: { "Content-Type": "application/json" }
  })
})
```

---

## AI Integration

### Supported AI Models

| Model | Kullanım | API | Maliyet |
|-------|----------|-----|---------|
| SDXL | Static wallpaper | Replicate | ~$0.02/img |
| SD 3.5 | High quality static | fal.ai | ~$0.06/img |
| Pika | Image-to-video | Pika API | ~$0.40/video |
| Runway | Premium video | Runway API | ~$1.50/video |

### Generation Flow

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│  User   │────▶│  App    │────▶│ Backend │────▶│  AI API │
│ Request │     │ (Swift) │     │(Supabase│     │(Replicate│
└─────────┘     └─────────┘     └─────────┘     └─────────┘
                    │                │                │
                    │                │                │
                    │   ┌────────────┘                │
                    │   │                             │
                    │   ▼                             │
                    │ Validate                        │
                    │ Credits                         │
                    │   │                             │
                    │   └────────────────────────────▶│
                    │                                 │
                    │              Generate           │
                    │◀────────────────────────────────│
                    │          (async webhook)        │
                    │                                 │
                    ▼
              Save & Display
```

---

## Performance Considerations

### CPU Optimization

```swift
class PerformanceMonitor {
    // Hedef: < 5% CPU kullanımı

    func shouldPausePlayback() -> Bool {
        // Pil modunda
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return true }

        // Tam ekran uygulama varsa
        if isFullscreenAppActive() { return true }

        // CPU yüksekse
        if currentCPUUsage() > 0.8 { return true }

        return false
    }
}
```

### Memory Management

- Video buffer: Max 3 frame ahead
- Thumbnail cache: LRU, max 100MB
- Generation results: Clear after apply

---

## Security

### Data Protection

- All API keys stored in Keychain
- User data encrypted at rest (Supabase)
- HTTPS only
- No analytics without consent

### Sandboxing

```xml
<!-- Entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

---

## File Structure

```
Wallnetic/
├── Wallnetic.xcodeproj
├── Wallnetic/
│   ├── App/
│   │   ├── WallneticApp.swift
│   │   └── AppDelegate.swift
│   ├── Views/
│   │   ├── Main/
│   │   ├── Gallery/
│   │   ├── Generate/
│   │   └── Settings/
│   ├── ViewModels/
│   ├── Models/
│   ├── Services/
│   ├── Engine/
│   ├── Network/
│   ├── Utils/
│   └── Resources/
│       ├── Assets.xcassets
│       └── Localizable.strings
├── WallneticTests/
└── WallneticUITests/
```

---

## Dependencies

### Swift Packages

```swift
// Package.swift
dependencies: [
    // Networking
    .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0"),

    // Payments
    .package(url: "https://github.com/RevenueCat/purchases-ios", from: "4.0.0"),

    // Utils
    .package(url: "https://github.com/kean/Nuke", from: "12.0.0"),  // Image loading
    .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.0.0"),  // HTML parsing
]
```

---

## Deployment

### Distribution Options

1. **Mac App Store** (Recommended)
   - Wider reach
   - Built-in payments
   - Sandboxed

2. **Direct Download**
   - More flexibility
   - No Apple cut (outside payments)
   - Needs notarization

### CI/CD Pipeline

```yaml
# .github/workflows/build.yml
name: Build & Test

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build
        run: xcodebuild -scheme Wallnetic -configuration Release
      - name: Test
        run: xcodebuild test -scheme Wallnetic
```
