# GitHub Issues - Başlangıç Task Listesi

> Bu dosya projeye başlarken GitHub'da oluşturulacak issue'ları içerir.
> Her issue için `gh issue create` komutu kullanılabilir.

---

## Phase 0: Hazırlık ve Öğrenme

### Milestone: "Phase 0 - Setup & Learning"

```bash
# Milestone oluştur
gh api repos/{owner}/wallnetic/milestones -f title="Phase 0 - Setup & Learning" -f description="Swift öğrenme ve geliştirme ortamı kurulumu"

# Labels oluştur
gh label create "phase-0" --color "0E8A16" --description "Hazırlık aşaması"
gh label create "learning" --color "D4C5F9" --description "Öğrenme ile ilgili"
gh label create "setup" --color "C2E0C6" --description "Kurulum ile ilgili"
gh label create "P0" --color "B60205" --description "Critical priority"
gh label create "P1" --color "D93F0B" --description "High priority"
gh label create "P2" --color "FBCA04" --description "Medium priority"
```

### Issues

#### Swift Öğrenme

```bash
gh issue create \
  --title "[TASK] Swift Basics - Variables, Types, Functions" \
  --body "## Description
Swift temellerini öğren: değişkenler, tipler, fonksiyonlar.

## Resources
- [Swift.org - The Basics](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/thebasics/)
- [Hacking with Swift - Day 1-3](https://www.hackingwithswift.com/100/swiftui)

## Acceptance Criteria
- [ ] Variables ve constants (var/let) anlama
- [ ] Temel data types (String, Int, Double, Bool)
- [ ] Functions yazabilme
- [ ] 3 mini egzersiz tamamlama

## Estimated
2-3 gün" \
  --label "phase-0,learning,P0" \
  --milestone "Phase 0 - Setup & Learning"
```

```bash
gh issue create \
  --title "[TASK] Swift Collections & Control Flow" \
  --body "## Description
Swift collections ve control flow yapılarını öğren.

## Topics
- Arrays, Dictionaries, Sets
- if/else, switch
- for loops, while
- guard statements

## Acceptance Criteria
- [ ] Array işlemleri yapabilme
- [ ] Dictionary kullanabilme
- [ ] Control flow yapılarını anlama
- [ ] 3 mini egzersiz

## Estimated
2 gün" \
  --label "phase-0,learning,P0" \
  --milestone "Phase 0 - Setup & Learning"
```

```bash
gh issue create \
  --title "[TASK] Swift OOP - Classes, Structs, Protocols" \
  --body "## Description
Swift OOP konseptlerini öğren.

## Topics
- Class vs Struct farkları
- Properties (stored, computed)
- Methods
- Protocols
- Extensions

## Acceptance Criteria
- [ ] Class ve Struct farkını anlama
- [ ] Protocol yazabilme
- [ ] Extension kullanabilme
- [ ] Mini proje: Basit bir data model

## Estimated
3 gün" \
  --label "phase-0,learning,P0" \
  --milestone "Phase 0 - Setup & Learning"
```

```bash
gh issue create \
  --title "[TASK] SwiftUI Fundamentals" \
  --body "## Description
SwiftUI temellerini öğren.

## Topics
- View protocol
- Text, Image, Button
- Modifiers
- VStack, HStack, ZStack
- @State, @Binding

## Resources
- [Apple SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [100 Days of SwiftUI - Week 1-2](https://www.hackingwithswift.com/100/swiftui)

## Acceptance Criteria
- [ ] Basit UI oluşturabilme
- [ ] State management anlama
- [ ] Mini proje: Counter app

## Estimated
5 gün" \
  --label "phase-0,learning,P0" \
  --milestone "Phase 0 - Setup & Learning"
```

```bash
gh issue create \
  --title "[TASK] macOS App Development Basics" \
  --body "## Description
macOS spesifik geliştirme konularını öğren.

## Topics
- macOS app structure
- AppKit basics (NSWindow, NSView)
- Menu bar apps
- File system access
- Permissions

## Acceptance Criteria
- [ ] Basit macOS app oluşturabilme
- [ ] Menu bar app yapabilme
- [ ] Dosya seçme dialog kullanabilme

## Estimated
4 gün" \
  --label "phase-0,learning,P1" \
  --milestone "Phase 0 - Setup & Learning"
```

```bash
gh issue create \
  --title "[TASK] Mini Project - Video Player for macOS" \
  --body "## Description
Öğrenilenleri pekiştirmek için basit video player yap.

## Requirements
- Video dosyası seçme
- AVPlayer ile oynatma
- Play/Pause kontrolleri
- SwiftUI arayüz

## Acceptance Criteria
- [ ] Video dosyası açabilme
- [ ] Play/Pause çalışıyor
- [ ] Progress bar
- [ ] Ses kontrolü

## Why
Bu proje Wallnetic'in temel video işlevselliği için pratik.

## Estimated
1 hafta" \
  --label "phase-0,learning,P0" \
  --milestone "Phase 0 - Setup & Learning"
```

#### Geliştirme Ortamı

```bash
gh issue create \
  --title "[TASK] Xcode & Development Environment Setup" \
  --body "## Description
Geliştirme ortamını kur.

## Checklist
- [ ] Xcode 15+ indir ve kur
- [ ] Command Line Tools kur
- [ ] SF Symbols app indir
- [ ] SwiftLint kur (homebrew)
- [ ] Git config

## Commands
\`\`\`bash
xcode-select --install
brew install swiftlint
\`\`\`

## Estimated
2 saat" \
  --label "phase-0,setup,P0" \
  --milestone "Phase 0 - Setup & Learning"
```

```bash
gh issue create \
  --title "[TASK] Apple Developer Account Setup" \
  --body "## Description
Apple Developer hesabı oluştur (App Store için gerekli).

## Steps
1. [developer.apple.com](https://developer.apple.com) git
2. Apple ID ile giriş yap
3. Developer Program'a katıl ($99/yıl)

## Note
- Hesap onayı 24-48 saat sürebilir
- TestFlight için gerekli
- App Store release için zorunlu

## Estimated
1-2 gün (onay süresi)" \
  --label "phase-0,setup,P1" \
  --milestone "Phase 0 - Setup & Learning"
```

```bash
gh issue create \
  --title "[TASK] Research - ScreenSaver.framework Documentation" \
  --body "## Description
macOS'ta live wallpaper yapmanın yollarını araştır.

## Topics to Research
- ScreenSaver.framework nasıl çalışıyor
- Desktop window level
- CGWindowLevel API
- NSWindow.Level
- Existing open source implementations

## Resources
- [Apple ScreenSaver Docs](https://developer.apple.com/documentation/screensaver)
- [Equinox GitHub](https://github.com/rlxone/Equinox)
- Apple Developer Forums

## Deliverable
- Teknik yaklaşım kararı
- Pros/cons listesi

## Estimated
4 saat" \
  --label "phase-0,research,P0" \
  --milestone "Phase 0 - Setup & Learning"
```

```bash
gh issue create \
  --title "[TASK] Research - Competitor Apps Analysis" \
  --body "## Description
Rakip uygulamaları indir ve test et.

## Apps to Test
- [ ] Backdrop (Cindori) - $2.99/mo trial
- [ ] WallMotion - $15
- [ ] ScreenPlay (free, open source)
- [ ] 4K Live Wallpaper

## Analysis Points
- Özellikler
- Performans (CPU/Memory)
- UX/UI
- Fiyatlandırma
- Eksiklikler

## Deliverable
Competitor analysis document

## Estimated
3-4 saat" \
  --label "phase-0,research,P1" \
  --milestone "Phase 0 - Setup & Learning"
```

---

## Phase 1: MVP

### Milestone: "Phase 1 - MVP"

```bash
gh api repos/{owner}/wallnetic/milestones -f title="Phase 1 - MVP" -f description="Temel live wallpaper işlevselliği"

gh label create "phase-1" --color "1D76DB" --description "MVP aşaması"
gh label create "core" --color "5319E7" --description "Core engine"
gh label create "ui" --color "006B75" --description "User interface"
```

### Issues

```bash
gh issue create \
  --title "[TASK] Create Xcode Project Structure" \
  --body "## Description
Wallnetic Xcode projesini oluştur.

## Structure
- macOS App template
- MVVM architecture
- Folder structure (Views, ViewModels, Models, Services, Engine)
- SwiftUI lifecycle

## Checklist
- [ ] Xcode project oluştur
- [ ] Folder structure
- [ ] Basic app delegate
- [ ] Info.plist config
- [ ] .gitignore

## Estimated
2 saat" \
  --label "phase-1,setup,P0" \
  --milestone "Phase 1 - MVP"
```

```bash
gh issue create \
  --title "[TASK] Implement Desktop Window Layer" \
  --body "## Description
Masaüstü arkasında video gösterecek pencere katmanını oluştur.

## Technical
- NSWindow with desktop level
- CGWindowLevelForKey(.desktopWindow) + 1
- Borderless, non-activating
- Spans entire screen

## Acceptance Criteria
- [ ] Pencere masaüstü ikonlarının arkasında
- [ ] Pencere tüm ekranı kaplıyor
- [ ] Pencere click almıyor (passthrough)
- [ ] Multi-space desteği

## References
- #[research issue number]

## Estimated
1 gün" \
  --label "phase-1,core,P0" \
  --milestone "Phase 1 - MVP"
```

```bash
gh issue create \
  --title "[TASK] Video Playback with AVFoundation" \
  --body "## Description
AVPlayer ile video oynatma implementasyonu.

## Requirements
- MP4, MOV, HEVC format desteği
- Seamless loop
- Hardware decoding
- Low CPU usage

## Implementation
- AVPlayer + AVPlayerLayer
- Video composition for looping
- Background playback

## Acceptance Criteria
- [ ] Video dosyası oynatabilme
- [ ] Loop çalışıyor
- [ ] < 5% CPU kullanımı
- [ ] Hardware acceleration

## Estimated
2-3 gün" \
  --label "phase-1,core,P0" \
  --milestone "Phase 1 - MVP"
```

```bash
gh issue create \
  --title "[TASK] Menu Bar App Implementation" \
  --body "## Description
System menu bar'da çalışan uygulama yap.

## Features
- Status bar icon
- Dropdown menu
- Play/Pause toggle
- Change wallpaper
- Preferences
- Quit

## Technical
- NSStatusItem
- NSMenu
- NSMenuItem

## Acceptance Criteria
- [ ] Menu bar'da ikon görünüyor
- [ ] Click'te menu açılıyor
- [ ] Play/Pause çalışıyor
- [ ] Quit app çalışıyor

## Estimated
4 saat" \
  --label "phase-1,ui,P0" \
  --milestone "Phase 1 - MVP"
```

```bash
gh issue create \
  --title "[TASK] Main Window - Wallpaper Selection UI" \
  --body "## Description
Ana uygulama penceresini tasarla ve implement et.

## Features
- Wallpaper gallery/grid
- Video preview
- Import button
- Settings access

## Design
- SwiftUI
- Sidebar + Content layout
- Thumbnail grid
- Video preview on hover

## Acceptance Criteria
- [ ] Video listesi gösteriliyor
- [ ] Önizleme çalışıyor
- [ ] Dosya import edebilme
- [ ] Wallpaper'ı apply edebilme

## Estimated
2-3 gün" \
  --label "phase-1,ui,P0" \
  --milestone "Phase 1 - MVP"
```

```bash
gh issue create \
  --title "[TASK] Multi-Monitor Support" \
  --body "## Description
Birden fazla monitör desteği ekle.

## Features
- Tüm monitörleri algılama
- Her monitöre farklı wallpaper
- Monitor ekleme/çıkarma handling

## Technical
- NSScreen.screens
- NotificationCenter for screen changes
- Per-screen window management

## Acceptance Criteria
- [ ] Tüm ekranlar listeleniyor
- [ ] Her ekrana wallpaper atanabiliyor
- [ ] Hot-plug çalışıyor

## Estimated
1-2 gün" \
  --label "phase-1,core,P1" \
  --milestone "Phase 1 - MVP"
```

```bash
gh issue create \
  --title "[TASK] Auto-Start on Login" \
  --body "## Description
Kullanıcı girişinde otomatik başlatma özelliği.

## Technical
- Login Items API (modern)
- ServiceManagement framework
- User preference toggle

## Acceptance Criteria
- [ ] Settings'de toggle var
- [ ] Login'de başlıyor
- [ ] Disable edilebilir

## Estimated
3 saat" \
  --label "phase-1,core,P1" \
  --milestone "Phase 1 - MVP"
```

```bash
gh issue create \
  --title "[TASK] Battery Mode - Auto Pause" \
  --body "## Description
Pil modunda otomatik duraklatma.

## Features
- Pil/şarj durumu algılama
- Low power mode algılama
- Otomatik pause/resume
- User preference

## Technical
- IOKit Power Management
- ProcessInfo.isLowPowerModeEnabled

## Acceptance Criteria
- [ ] Pil modunda pause
- [ ] Şarja takılınca resume
- [ ] Low power mode respect

## Estimated
3-4 saat" \
  --label "phase-1,core,P1" \
  --milestone "Phase 1 - MVP"
```

```bash
gh issue create \
  --title "[TASK] Performance Optimization & Testing" \
  --body "## Description
Performans optimizasyonu ve test.

## Goals
- < 5% CPU usage (idle)
- < 200MB RAM
- Smooth 60fps playback
- No memory leaks

## Tools
- Instruments (CPU, Memory, Energy)
- Activity Monitor

## Checklist
- [ ] CPU profiling
- [ ] Memory leak check
- [ ] Energy impact assessment
- [ ] Optimization

## Estimated
2-3 gün" \
  --label "phase-1,core,P0" \
  --milestone "Phase 1 - MVP"
```

---

## Quick Start Commands

```bash
# Repo'yu GitHub'da oluşturduktan sonra:
cd /Volumes/Backup/cloud/git/wallnetic
git init
git add .
git commit -m "Initial commit: Project structure and documentation"
git branch -M main
git remote add origin https://github.com/[username]/wallnetic.git
git push -u origin main

# GitHub CLI ile milestones oluştur
gh api repos/[username]/wallnetic/milestones -f title="Phase 0 - Setup & Learning"
gh api repos/[username]/wallnetic/milestones -f title="Phase 1 - MVP"
gh api repos/[username]/wallnetic/milestones -f title="Phase 2 - AI Integration"

# Labels oluştur
gh label create "phase-0" --color "0E8A16"
gh label create "phase-1" --color "1D76DB"
gh label create "phase-2" --color "B60205"
gh label create "learning" --color "D4C5F9"
gh label create "core" --color "5319E7"
gh label create "ui" --color "006B75"
gh label create "P0" --color "B60205"
gh label create "P1" --color "D93F0B"
gh label create "P2" --color "FBCA04"
```

---

## Not

Bu dosyayı referans olarak kullan. Her issue'yu `gh issue create` ile oluşturabilir veya GitHub web arayüzünden manuel ekleyebilirsin.

Issue oluşturduktan sonra GitHub Projects board kullanarak Kanban tarzı yönetebilirsin.
