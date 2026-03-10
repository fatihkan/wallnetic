# Swift Öğrenme Planı

> Swift ve SwiftUI öğrenmek için yapılandırılmış plan

## Neden Swift?

- macOS native uygulamalar için **en iyi** seçenek
- SwiftUI ile modern, declarative UI geliştirme
- Apple ekosistemiyle tam entegrasyon
- Performans ve güvenlik

---

## Öğrenme Yol Haritası

### Hafta 1: Swift Temelleri

#### Gün 1-2: Basics
- [ ] Variables & Constants (`var`, `let`)
- [ ] Data Types (String, Int, Double, Bool)
- [ ] Type inference ve type annotation
- [ ] String interpolation

**Kaynak:** [Swift.org - The Basics](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/thebasics/)

#### Gün 3-4: Collections & Control Flow
- [ ] Arrays, Dictionaries, Sets
- [ ] If/else, switch statements
- [ ] For loops, while loops
- [ ] Guard statements

**Kaynak:** [Swift.org - Collection Types](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/collectiontypes/)

#### Gün 5-7: Functions & Closures
- [ ] Function syntax
- [ ] Parameters & return values
- [ ] Closures (lambdas)
- [ ] Trailing closure syntax

**Kaynak:** [Swift.org - Functions](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/functions/)

---

### Hafta 2: OOP ve Swift Özellikleri

#### Gün 1-2: Classes & Structs
- [ ] Class vs Struct farkları
- [ ] Properties (stored, computed)
- [ ] Methods
- [ ] Initializers

#### Gün 3-4: Protocols & Extensions
- [ ] Protocol definition
- [ ] Protocol conformance
- [ ] Extensions
- [ ] Protocol extensions

#### Gün 5-6: Optionals & Error Handling
- [ ] Optional types (`?`, `!`)
- [ ] Optional binding (`if let`, `guard let`)
- [ ] Nil coalescing (`??`)
- [ ] Try/catch/throw

#### Gün 7: Enums & Generics
- [ ] Enum with associated values
- [ ] Generic functions
- [ ] Generic types

---

### Hafta 3: SwiftUI

#### Gün 1-2: SwiftUI Basics
- [ ] View protocol
- [ ] Text, Image, Button
- [ ] Modifiers (`.font()`, `.padding()`, etc.)
- [ ] VStack, HStack, ZStack

**Proje:** Basit bir "Hello World" UI

#### Gün 3-4: State Management
- [ ] @State
- [ ] @Binding
- [ ] @StateObject
- [ ] @ObservedObject
- [ ] @EnvironmentObject

**Proje:** Counter app

#### Gün 5-6: Navigation & Lists
- [ ] NavigationStack
- [ ] List
- [ ] ForEach
- [ ] Sheets & Alerts

**Proje:** Todo list app

#### Gün 7: macOS Specific
- [ ] macOS window management
- [ ] Menu bar apps
- [ ] Settings/Preferences window
- [ ] NSWindow, NSView (AppKit basics)

---

## Önerilen Kaynaklar

### Ücretsiz

| Kaynak | Açıklama | Link |
|--------|----------|------|
| **Swift.org** | Resmi dokümantasyon | [swift.org/documentation](https://www.swift.org/documentation/) |
| **Hacking with Swift** | En iyi ücretsiz kaynak | [hackingwithswift.com](https://www.hackingwithswift.com/) |
| **100 Days of SwiftUI** | Yapılandırılmış kurs | [hackingwithswift.com/100/swiftui](https://www.hackingwithswift.com/100/swiftui) |
| **Apple Tutorials** | Resmi Apple tutorials | [developer.apple.com/tutorials](https://developer.apple.com/tutorials/swiftui) |
| **Stanford CS193p** | Stanford üniversite kursu | [YouTube](https://www.youtube.com/playlist?list=PLpGHT1n4-mAsxuRxVPv7kj4-dQYoC3VVu) |
| **Swift Playgrounds** | iPad/Mac app ile öğren | App Store |
| **Kavsoft** | SwiftUI tutorials (YouTube) | [youtube.com/@Kavsoft](https://www.youtube.com/@Kavsoft) |

### Ücretli (İsteğe Bağlı)

| Kaynak | Fiyat | Açıklama |
|--------|-------|----------|
| Hacking with Swift+ | $40/ay | Premium içerik |
| Ray Wenderlich | $20/ay | Video kurslar |
| Udemy Kursları | $15-30 | Çeşitli |

---

## Pratik Projeler

### Proje 1: Hello macOS
**Zorluk:** Kolay
**Süre:** 1-2 saat
**Öğrenilecek:** Xcode, SwiftUI basics

```swift
import SwiftUI

@main
struct HelloApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello, Wallnetic!")
                .font(.largeTitle)
                .padding()
        }
    }
}
```

### Proje 2: Menu Bar App
**Zorluk:** Orta
**Süre:** 3-4 saat
**Öğrenilecek:** Menu bar apps, NSStatusItem

Basit bir menu bar uygulaması yap:
- System tray'de ikon göster
- Click'te menu aç
- Quit butonu

### Proje 3: Image Viewer
**Zorluk:** Orta
**Süre:** 4-5 saat
**Öğrenilecek:** FileManager, Image handling

- Dosya seçme dialog
- Seçilen resmi gösterme
- Drag & drop desteği

### Proje 4: Video Player
**Zorluk:** Orta-Zor
**Süre:** 5-6 saat
**Öğrenilecek:** AVFoundation, AVPlayer

- Video dosyası aç
- Play/Pause kontrolleri
- Progress bar
- Ses kontrolü

### Proje 5: Simple Wallpaper Setter
**Zorluk:** Zor
**Süre:** 8-10 saat
**Öğrenilecek:** NSWorkspace, Desktop API

- Resim seç
- Desktop wallpaper olarak ayarla
- Tüm ekranlar için

---

## macOS Spesifik Konular

### Wallnetic için kritik konular:

1. **ScreenSaver.framework**
   - Screensaver nasıl çalışır
   - Custom screensaver yazma
   - Desktop layer'a erişim

2. **Metal Framework**
   - GPU rendering
   - Video playback optimization
   - Low CPU usage

3. **AVFoundation**
   - Video playback
   - Supported formats
   - Hardware decoding

4. **AppKit Integration**
   - NSWindow
   - NSScreen (multi-monitor)
   - NSWorkspace

5. **Sandboxing & Permissions**
   - File system access
   - Screen recording permission
   - Desktop access

---

## Günlük Çalışma Planı

```
Hafta içi (haftada 5 gün):
├── 30 dk: Teori/dokümantasyon okuma
├── 45 dk: Tutorial takibi
├── 45 dk: Pratik kodlama
└── 15 dk: Not alma, review

Hafta sonu (opsiyonel):
└── 2-3 saat: Mini proje
```

---

## İlerleme Takibi

### Swift Basics Checklist
- [ ] Variables & Constants
- [ ] Data Types
- [ ] Operators
- [ ] Control Flow (if, switch, loops)
- [ ] Functions
- [ ] Closures
- [ ] Optionals
- [ ] Error Handling
- [ ] Classes
- [ ] Structs
- [ ] Protocols
- [ ] Extensions
- [ ] Enums
- [ ] Generics

### SwiftUI Checklist
- [ ] Views & Modifiers
- [ ] Layout (Stacks)
- [ ] State Management
- [ ] Navigation
- [ ] Lists & ForEach
- [ ] Sheets & Alerts
- [ ] Gestures
- [ ] Animations
- [ ] Custom Views

### macOS Checklist
- [ ] Basic macOS App
- [ ] Menu Bar App
- [ ] Window Management
- [ ] File Handling
- [ ] AVFoundation basics
- [ ] Screen/Display APIs

---

## Tips

1. **Günlük yaz kod** - Az da olsa her gün
2. **Copy-paste yapma** - Elle yaz, kas hafızası
3. **Hata yap** - En iyi öğrenme yolu
4. **Xcode'u tanı** - Shortcuts, debugging
5. **Documentation oku** - Apple docs çok iyi
6. **Topluluktan yardım al** - Stack Overflow, Reddit

---

## Yardımcı Araçlar

- **Xcode** - Ana IDE
- **SF Symbols** - Apple'ın ikon kütüphanesi
- **SwiftUI Inspector** - UI debugging
- **Instruments** - Performance profiling

---

Başarılar! 🚀
