# Wallnetic - App Store Submission Guide

Bu dokuman, Wallnetic uygulamasini Mac App Store'a gondermek icin gereken tum adimlari ve icerikleri icerir.

**Version:** 1.0.0 (Phase 1 - Live Video Wallpapers)

---

## Icindekiler

1. [On Gereksinimler](#1-on-gereksinimler)
2. [Apple Developer Hesabi](#2-apple-developer-hesabi)
3. [Sertifikalar ve Profiller](#3-sertifikalar-ve-profiller)
4. [App Store Connect Ayarlari](#4-app-store-connect-ayarlari)
5. [Uygulama Metadata](#5-uygulama-metadata)
6. [Ekran Goruntuleri](#6-ekran-goruntuleri)
7. [App Icon](#7-app-icon)
8. [Gizlilik Politikasi](#8-gizlilik-politikasi)
9. [Xcode Ayarlari](#9-xcode-ayarlari)
10. [Archive ve Upload](#10-archive-ve-upload)
11. [TestFlight](#11-testflight)
12. [App Review Sureci](#12-app-review-sureci)
13. [Checklist](#13-checklist)

---

## 1. On Gereksinimler

### Gerekli Araclar
- [x] macOS Sequoia veya uzeri
- [x] Xcode 15.0 veya uzeri
- [x] Apple Developer hesabi ($99/yil)
- [x] Transporter app (App Store'dan ucretsiz)

### Teknik Gereksinimler
- [x] Minimum macOS deployment target: macOS 13.0+
- [x] Universal binary (Apple Silicon + Intel)
- [x] App Sandbox enabled
- [x] Hardened Runtime enabled
- [x] Notarization icin kod imzalama

---

## 2. Apple Developer Hesabi

### Kayit Adimlari
1. https://developer.apple.com adresine gidin
2. "Account" > "Enroll" secin
3. Apple ID ile giris yapin
4. Bireysel veya sirket olarak kayit olun
5. $99 yillik ucret odeyin
6. 24-48 saat icerisinde onaylanir

---

## 3. Sertifikalar ve Profiller

### 3.1 Sertifika Olusturma

**Xcode'da Otomatik:**
1. Xcode > Settings > Accounts
2. Apple ID ekleyin
3. Team seciniz
4. "Manage Certificates" > "+" > "Apple Distribution"

### 3.2 App ID Olusturma

1. Developer Portal > Identifiers > "+"
2. "App IDs" secin
3. Platform: macOS
4. Bundle ID: `com.wallnetic.app` (Explicit)
5. Capabilities secin:
   - [x] App Sandbox
   - [x] Hardened Runtime

### 3.3 Provisioning Profile

1. Developer Portal > Profiles > "+"
2. "Mac App Store" > "Mac App Distribution"
3. App ID secin: com.wallnetic.app
4. Sertifika secin
5. Profili indirin

---

## 4. App Store Connect Ayarlari

### 4.1 Yeni App Olusturma

1. https://appstoreconnect.apple.com gidin
2. "My Apps" > "+" > "New App"
3. Asagidaki bilgileri girin:

| Alan | Deger |
|------|-------|
| Platform | macOS |
| Name | Wallnetic |
| Primary Language | English (U.S.) |
| Bundle ID | com.wallnetic.app |
| SKU | WALLNETIC001 |
| User Access | Full Access |

### 4.2 App Information

| Alan | Deger |
|------|-------|
| **Name** | Wallnetic |
| **Subtitle** | Live Video Wallpapers |
| **Primary Category** | Graphics & Design |
| **Secondary Category** | Entertainment |
| **Content Rights** | Does not contain third-party content |
| **Age Rating** | 4+ (No objectionable content) |

---

## 5. Uygulama Metadata

### 5.1 App Name & Subtitle

```
Name: Wallnetic
Subtitle: Live Video Wallpapers
```

### 5.2 Promotional Text (170 karakter)
```
Transform your Mac desktop with stunning live video wallpapers. Multi-monitor support, collections, favorites, and seamless Metal-powered playback!
```

### 5.3 Description (4000 karakter)

```
Wallnetic brings your Mac desktop to life with beautiful live video wallpapers. Import your favorite video clips and watch them loop seamlessly as your desktop background.

KEY FEATURES

Easy Video Import
• Drag and drop video files directly into the app
• Support for MP4, MOV, and other common formats
• Instant preview before setting as wallpaper

Library Management
• Create custom collections to organize wallpapers
• Mark favorites for quick access
• Search through your library instantly
• View recently added wallpapers

Multi-Monitor Support
• Set different wallpapers for each display
• Same wallpaper across all monitors option
• Automatic detection of connected displays

Smart Playback
• Metal-accelerated video rendering
• Pause automatically on battery power
• Pause when fullscreen apps are active
• Auto-resume when conditions change

Customization
• Dark, Light, or System theme
• Launch at login option
• Menu bar quick access

WHY WALLNETIC?

Static wallpapers are boring. Wallnetic transforms your desktop into a dynamic, living canvas. Whether you prefer calming nature scenes, abstract animations, or cinematic loops - your desktop becomes an experience.

PERFORMANCE FOCUSED

Metal rendering for efficient GPU-accelerated playback. Smart power management ensures your battery isn't drained unnecessarily.

REQUIREMENTS

• macOS 13.0 or later
• Apple Silicon or Intel Mac
• Video files (MP4, MOV recommended)

Transform your desktop today with Wallnetic!
```

### 5.4 Keywords (100 karakter)

```
wallpaper,live wallpaper,video wallpaper,desktop,background,animated,loop,multi-monitor,macOS
```

### 5.5 What's New (Version 1.0.0)

```
Initial release of Wallnetic!

• Import video files as live wallpapers
• Multi-monitor support
• Library with collections and favorites
• Smart playback controls
• Metal-accelerated rendering
• Dark/Light/System themes
```

### 5.6 URLs

| Alan | URL |
|------|-----|
| Support URL | `https://github.com/fatihkan/wallnetic/issues` |
| Marketing URL | `https://github.com/fatihkan/wallnetic` |
| Privacy Policy URL | `https://github.com/fatihkan/wallnetic/blob/main/PRIVACY.md` |

---

## 6. Ekran Goruntuleri

### 6.1 Gerekli Boyutlar

Mac App Store icin en az 1 screenshot gerekli:

| Cihaz | Boyut | Gerekli |
|-------|-------|---------|
| Mac (16" Retina) | 3456 x 2234 | Zorunlu |
| Mac (13" Retina) | 2880 x 1800 | Opsiyonel |

### 6.2 Screenshot Listesi (Onerilen 5 adet)

1. **Ana Ekran - Kutuphane**
   - Tum wallpaper'larin gorundugu grid gorunumu
   - Dosya: `screenshot_01_library.png`

2. **Collections**
   - Koleksiyon yonetimi
   - Dosya: `screenshot_02_collections.png`

3. **Settings - General**
   - Genel ayarlar
   - Dosya: `screenshot_03_settings.png`

4. **Multi-Monitor**
   - Display ayarlari
   - Dosya: `screenshot_04_displays.png`

5. **Theme Options**
   - Dark/Light mode
   - Dosya: `screenshot_05_theme.png`

### 6.3 Screenshot Alma

```bash
# Retina cozunurlukde screenshot
screencapture -x screenshot.png

# Belirli pencere
screencapture -w screenshot.png
```

---

## 7. App Icon

### 7.1 Icon Boyutlari

| Boyut | Dosya Adi |
|-------|-----------|
| 16x16 | icon_16x16.png |
| 32x32 | icon_32x32.png |
| 128x128 | icon_128x128.png |
| 256x256 | icon_256x256.png |
| 512x512 | icon_512x512.png |
| 1024x1024 | AppIcon.png |

### 7.2 App Store Icon

- Boyut: 1024x1024 px
- Format: PNG (seffaf arka plan olmamali)

---

## 8. Gizlilik Politikasi

### 8.1 App Privacy Details (App Store Connect)

**Data Collection:** Select **"Data Not Collected"**

Wallnetic:
- Does not collect personal information
- Does not track usage or analytics
- Does not connect to external servers
- Works entirely offline

### 8.2 Privacy Policy URL

```
https://github.com/fatihkan/wallnetic/blob/main/PRIVACY.md
```

---

## 9. Xcode Ayarlari

### 9.1 Project Settings

```
Bundle Identifier: com.wallnetic.app
Version: 1.0.0
Build: 1
Deployment Target: macOS 13.0
```

### 9.2 Signing & Capabilities

```
Team: [Your Team]
Signing Certificate: Apple Distribution
Provisioning Profile: Wallnetic App Store
```

### 9.3 Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
    <key>com.apple.security.assets.movies.read-only</key>
    <true/>
</dict>
</plist>
```

### 9.4 Info.plist

```xml
<key>CFBundleName</key>
<string>Wallnetic</string>

<key>CFBundleDisplayName</key>
<string>Wallnetic</string>

<key>CFBundleIdentifier</key>
<string>com.wallnetic.app</string>

<key>CFBundleVersion</key>
<string>1</string>

<key>CFBundleShortVersionString</key>
<string>1.0.0</string>

<key>LSMinimumSystemVersion</key>
<string>13.0</string>

<key>LSApplicationCategoryType</key>
<string>public.app-category.graphics-design</string>

<key>NSHumanReadableCopyright</key>
<string>Copyright 2026 Wallnetic. All rights reserved.</string>

<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

---

## 10. Archive ve Upload

### 10.1 Archive Olusturma

1. Xcode'da scheme "Any Mac" olarak ayarlayin
2. Product > Archive secin
3. Archive tamamlaninca Organizer acilir

### 10.2 App Store Connect'e Upload

1. Organizer'da archive secin
2. "Distribute App" tiklayin
3. "App Store Connect" secin
4. "Upload" secin
5. Signing options'i kontrol edin
6. "Upload" ile gonderin

---

## 11. TestFlight

### 11.1 Internal Testing

1. App Store Connect > TestFlight
2. Build gorunene kadar bekleyin (5-30 dk)
3. "Internal Testing" grubuna kendinizi ekleyin
4. TestFlight app'i ile test edin

### 11.2 Beta Test Notu

```
Welcome to Wallnetic Beta!

What's being tested:
- Video wallpaper import and playback
- Multi-monitor support
- Library management with collections
- Theme settings

Please report bugs to: support@wallnetic.app

Thank you for testing!
```

---

## 12. App Review Sureci

### 12.1 Review Notes

```
Thank you for reviewing Wallnetic!

HOW TO TEST:
1. Open Wallnetic from Applications
2. Click "Import Videos" or drag video files into the app
3. Click on a video thumbnail to preview
4. Click "Set as Wallpaper" to apply
5. Check Settings for theme, playback, and display options

SUPPORTED FORMATS:
MP4, MOV, M4V video files

The app works completely offline and requires no account or external services.

For questions: support@wallnetic.app
```

### 12.2 Common Rejection Reasons

| Neden | Cozum |
|-------|-------|
| Incomplete information | Review notes'u detayli yazin |
| Bugs/crashes | TestFlight'ta iyice test edin |
| Placeholder content | Gercek icerik kullanin |
| Privacy issues | Privacy policy'yi tamamlayin |

### 12.3 Review Suresi

- Ilk submission: 24-48 saat
- Resubmission: 24 saat

---

## 13. Checklist

### Pre-Submission Checklist

**Developer Account:**
- [ ] Apple Developer Program uyeligi aktif
- [ ] Apple Distribution sertifikasi olusturuldu
- [ ] Provisioning profile olusturuldu

**App Store Connect:**
- [ ] App olusturuldu
- [ ] App Information dolduruldu
- [ ] Pricing (Free) ayarlandi
- [ ] App Privacy: "Data Not Collected" secildi

**Metadata:**
- [ ] App name girildi
- [ ] Subtitle girildi
- [ ] Description yazildi
- [ ] Keywords eklendi
- [ ] What's New yazildi
- [ ] Support URL eklendi
- [ ] Privacy Policy URL eklendi

**Assets:**
- [ ] App Icon (1024x1024) yuklendi
- [ ] Screenshots (min 1) yuklendi

**Xcode:**
- [ ] Bundle ID dogru
- [ ] Version ve Build numaralari ayarlandi
- [ ] Signing dogru yapilandirildi
- [ ] Entitlements tamamlandi
- [ ] Archive basariyla olusturuldu

**Testing:**
- [ ] Video import test edildi
- [ ] Multi-monitor test edildi
- [ ] Settings test edildi
- [ ] Crash yok

**Final:**
- [ ] Build upload edildi
- [ ] Build islendi (processing)
- [ ] Review notes yazildi
- [ ] Submit for Review

---

## Yardimci Linkler

- [App Store Connect](https://appstoreconnect.apple.com)
- [Apple Developer Portal](https://developer.apple.com)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Human Interface Guidelines - macOS](https://developer.apple.com/design/human-interface-guidelines/macos)

---

## Iletisim

- Email: support@wallnetic.app
- GitHub: https://github.com/fatihkan/wallnetic
- Twitter: [@KanFatih](https://twitter.com/KanFatih)

---

*Bu dokuman Wallnetic v1.0.0 (Phase 1) icin hazirlanmistir.*
*Son guncelleme: Mart 2026*
