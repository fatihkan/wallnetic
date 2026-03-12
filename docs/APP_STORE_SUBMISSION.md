# Wallnetic - App Store Submission Guide

Bu dokuman, Wallnetic uygulamasini Mac App Store'a gondermek icin gereken tum adimlari ve icerikleri icerir.

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

### Gerekli Bilgiler (Bireysel)
- Ad Soyad
- Adres
- Telefon
- Kredi karti

### Gerekli Bilgiler (Sirket)
- D-U-N-S numarasi
- Sirket adi ve adresi
- Yasal temsilci bilgileri

---

## 3. Sertifikalar ve Profiller

### 3.1 Sertifika Olusturma

**Xcode'da Otomatik:**
1. Xcode > Settings > Accounts
2. Apple ID ekleyin
3. Team seciniz
4. "Manage Certificates" > "+" > "Apple Distribution"

**Manuel (Keychain Access):**
1. Keychain Access > Certificate Assistant > Request a Certificate
2. Email ve isim girin
3. "Save to disk" secin
4. Developer Portal > Certificates > "+"
5. "Apple Distribution" secin
6. CSR dosyasini yukleyin
7. Sertifikayi indirip cift tiklayin

### 3.2 App ID Olusturma

1. Developer Portal > Identifiers > "+"
2. "App IDs" secin
3. Platform: macOS
4. Bundle ID: `com.wallnetic.app` (Explicit)
5. Capabilities secin:
   - [x] App Sandbox
   - [x] Hardened Runtime
   - [x] Network (Outgoing)

### 3.3 Provisioning Profile

1. Developer Portal > Profiles > "+"
2. "Mac App Store" > "Mac App Distribution"
3. App ID secin: com.wallnetic.app
4. Sertifika secin
5. Profili indirin
6. Xcode'a surukleyin veya cift tiklayin

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

**Name:** Wallnetic

**Subtitle:** AI Video Wallpapers

**Category:**
- Primary: Graphics & Design
- Secondary: Entertainment

**Content Rights:**
- Does not contain third-party content

**Age Rating:** 4+ (No objectionable content)

---

## 5. Uygulama Metadata

### 5.1 App Name & Subtitle

```
Name: Wallnetic
Subtitle: AI-Powered Live Video Wallpapers
```

### 5.2 Promotional Text (170 karakter)
```
Transform your Mac desktop with stunning AI-generated video wallpapers. Choose from 7 AI models including Kling, Minimax, Luma, and more. Create anime & cinematic loops!
```

### 5.3 Description (4000 karakter)

```
Wallnetic brings your Mac desktop to life with AI-generated video wallpapers. Create stunning anime scenes, cinematic landscapes, and mesmerizing loop animations with just a few clicks.

KEY FEATURES

AI Video Generation
• 7 powerful AI models to choose from
• Kling Standard & Pro - Perfect for anime and stylized content
• Minimax Hailuo - Best for anime expressions and characters
• Luma Ray - Realistic and smooth motion
• Runway Gen-3 - Cinematic quality videos
• Pika - Creative and artistic animations
• Wan 2.1 - Budget-friendly option

Easy to Use
• Simple text-to-video generation
• Image-to-video animation support
• Drag & drop your images to animate them
• Smart prompt suggestions for inspiration
• Real-time generation progress tracking

Customization Options
• Choose video duration (5 or 10 seconds)
• Multiple aspect ratios (16:9, 9:16, 1:1)
• Anime-optimized models for best results
• Cost estimates before generation

Library Management
• Organize wallpapers in collections
• Mark favorites for quick access
• View generation history
• Search and filter your library

Display Control
• Support for multiple monitors
• Different wallpaper per display
• Pause on battery power
• Pause during fullscreen apps
• Metal-accelerated playback

Additional Features
• Dark/Light/System theme support
• Customizable notifications
• Launch at login option
• Menu bar quick access

WHY WALLNETIC?

Unlike static wallpapers, Wallnetic creates dynamic, looping video wallpapers that bring your desktop to life. Our AI models are specifically chosen for creating seamless, beautiful animations that won't distract you while working.

Perfect for:
• Anime enthusiasts
• Content creators
• Streamers
• Anyone who wants a unique desktop

POWERED BY FAL.AI

Wallnetic uses fal.ai's unified API to access multiple AI video generation models. You'll need a fal.ai API key to generate videos - sign up for free at fal.ai.

PRIVACY FOCUSED

Your prompts and images are only sent to fal.ai for generation. We don't store or track your creations. See our privacy policy for details.

REQUIREMENTS

• macOS 13.0 or later
• Apple Silicon or Intel Mac
• Internet connection for AI generation
• fal.ai API key (free tier available)

Get started today and transform your Mac desktop into a living work of art!
```

### 5.4 Keywords (100 karakter)

```
wallpaper,live wallpaper,video wallpaper,AI,anime,desktop,background,generator,animated,loop
```

### 5.5 What's New (Version 1.0)

```
Initial release of Wallnetic!

• AI-powered video wallpaper generation
• 7 video AI models (Kling, Minimax, Luma, Runway, Pika, Wan)
• Text-to-video and image-to-video support
• Multi-monitor support
• Library management with collections
• Dark/Light mode support
• Metal-accelerated video playback
```

### 5.6 Support URL

```
https://wallnetic.app/support
```

### 5.7 Marketing URL

```
https://wallnetic.app
```

### 5.8 Privacy Policy URL

```
https://wallnetic.app/privacy
```

---

## 6. Ekran Goruntuleri

### 6.1 Gerekli Boyutlar

Mac App Store icin en az 1 screenshot gerekli:

| Cihaz | Boyut | Gerekli |
|-------|-------|---------|
| Mac (16" Retina) | 3456 x 2234 | Zorunlu |
| Mac (13" Retina) | 2880 x 1800 | Opsiyonel |

### 6.2 Screenshot Listesi (Onerilen 5-10 adet)

1. **Ana Ekran - Kutuphane**
   - Tum wallpaper'larin gorundugu grid gorunumu
   - Sidebar'da kategoriler
   - Dosya: `screenshot_01_library.png`

2. **AI Video Generator**
   - Prompt girisi ve model secimi
   - Ayarlar paneli gorunur
   - Dosya: `screenshot_02_generate.png`

3. **Model Secimi**
   - Tum 7 AI modelin listesi
   - Anime badge'leri gorunur
   - Dosya: `screenshot_03_models.png`

4. **Generation Progress**
   - Video olusturma sureci
   - Progress bar ve sure tahmini
   - Dosya: `screenshot_04_progress.png`

5. **Generated Video**
   - Basariyla olusturulmus video
   - Action butonlari
   - Dosya: `screenshot_05_result.png`

6. **Collections**
   - Koleksiyon yonetimi
   - Ozel koleksiyonlar
   - Dosya: `screenshot_06_collections.png`

7. **Settings - AI**
   - API key ayarlari
   - Model secimi
   - Dosya: `screenshot_07_settings_ai.png`

8. **Settings - Appearance**
   - Tema secenekleri
   - Dosya: `screenshot_08_settings_theme.png`

9. **Multi-Monitor**
   - Display ayarlari
   - Farkli wallpaper per monitor
   - Dosya: `screenshot_09_displays.png`

10. **Menu Bar**
    - Menu bar dropdown
    - Hizli erisim
    - Dosya: `screenshot_10_menubar.png`

### 6.3 Screenshot Alma Ipuclari

```bash
# Retina cozunurlukta screenshot
screencapture -x screenshot.png

# Belirli pencere
screencapture -w screenshot.png

# Gecikme ile (5 saniye)
screencapture -T 5 screenshot.png
```

### 6.4 Screenshot Tasarim Onerisi

- Koyu tema tercih edin (daha etkileyici)
- Anime icerikleri one cikarin
- Turkce degil Ingilizce arayuz gosterin
- Temiz, ornek verilerle dolu

---

## 7. App Icon

### 7.1 Icon Boyutlari

macOS icin gerekli boyutlar:

| Boyut | Dosya Adi | Kullanim |
|-------|-----------|----------|
| 16x16 | icon_16x16.png | Menu bar |
| 16x16@2x | icon_16x16@2x.png | Menu bar Retina |
| 32x32 | icon_32x32.png | Finder |
| 32x32@2x | icon_32x32@2x.png | Finder Retina |
| 128x128 | icon_128x128.png | App Store |
| 128x128@2x | icon_128x128@2x.png | App Store Retina |
| 256x256 | icon_256x256.png | Large icons |
| 256x256@2x | icon_256x256@2x.png | Large icons Retina |
| 512x512 | icon_512x512.png | App Store |
| 512x512@2x | icon_512x512@2x.png | App Store Retina |

### 7.2 App Store Icon

- Boyut: 1024x1024 px
- Format: PNG (seffaf arka plan olmamali)
- Dosya: `AppIcon.png`

### 7.3 Icon Tasarim Onerileri

```
Konsept: Canli video + AI
- Film karesi veya video oynatma ikonu
- AI/sparkle efekti
- Gradient renk paleti (mor-mavi-pembe)
- macOS Big Sur+ tarzi yuvarlatilmis kare
```

---

## 8. Gizlilik Politikasi

### 8.1 Privacy Policy (Ingilizce)

Asagidaki icerigi `https://wallnetic.app/privacy` adresinde yayinlayin:

```markdown
# Wallnetic Privacy Policy

Last updated: March 2026

## Introduction

Wallnetic ("we", "our", or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our macOS application.

## Information We Collect

### Information You Provide
- **API Keys**: Your fal.ai API key is stored securely in the macOS Keychain on your device only. We never transmit or store your API key on our servers.
- **Prompts and Images**: When generating videos, your prompts and source images are sent directly to fal.ai for processing. We do not store or have access to this content.

### Information Automatically Collected
- **App Usage**: We do not collect any analytics or usage data.
- **Crash Reports**: If you opt-in to Apple's crash reporting, anonymous crash data may be shared with us through App Store Connect.

## How We Use Your Information

- To generate AI videos through fal.ai's API
- To store your preferences locally on your device
- To manage your wallpaper library on your device

## Data Storage

All your data is stored locally on your Mac:
- Wallpapers: ~/Library/Application Support/Wallnetic/Library
- Preferences: macOS UserDefaults
- API Keys: macOS Keychain (encrypted)

We do not have access to any of this data.

## Third-Party Services

### fal.ai
We use fal.ai as our AI video generation provider. When you generate a video:
- Your prompt is sent to fal.ai
- Your source image (if provided) is sent to fal.ai
- The generated video is downloaded to your device

Please review fal.ai's privacy policy at https://fal.ai/privacy

## Children's Privacy

Wallnetic is not intended for children under 13. We do not knowingly collect information from children.

## Changes to This Policy

We may update this Privacy Policy from time to time. We will notify you of any changes by updating the "Last updated" date.

## Contact Us

If you have questions about this Privacy Policy, please contact us at:
- Email: privacy@wallnetic.app
- Website: https://wallnetic.app/support

## Your Rights

You can:
- Delete all local data by uninstalling the app
- Remove your API key at any time in Settings
- Clear your wallpaper library through the app

---

Wallnetic
Copyright 2026. All rights reserved.
```

### 8.2 App Privacy Details (App Store Connect)

App Store Connect'te "App Privacy" bolumunde:

**Data Types Collected:**

| Veri Tipi | Toplanma Durumu |
|-----------|-----------------|
| Contact Info | Toplanmiyor |
| Health & Fitness | Toplanmiyor |
| Financial Info | Toplanmiyor |
| Location | Toplanmiyor |
| Sensitive Info | Toplanmiyor |
| Contacts | Toplanmiyor |
| User Content | Toplanmiyor* |
| Browsing History | Toplanmiyor |
| Search History | Toplanmiyor |
| Identifiers | Toplanmiyor |
| Usage Data | Toplanmiyor |
| Diagnostics | Opsiyonel (Crash) |

*Notlar:*
- User Content (prompts/images) ucuncu parti servise (fal.ai) gonderilir ama biz saklamiyoruz
- "Data Not Collected" secenegini isaretleyin

---

## 9. Xcode Ayarlari

### 9.1 Project Settings

**General:**
```
Bundle Identifier: com.wallnetic.app
Version: 1.0.0
Build: 1
Deployment Target: macOS 13.0
```

**Signing & Capabilities:**
```
Team: [Your Team]
Signing Certificate: Apple Distribution
Provisioning Profile: Wallnetic App Store
```

### 9.2 Capabilities (Entitlements)

`Wallnetic.entitlements` dosyasi:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
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

### 9.3 Build Settings

```
ENABLE_HARDENED_RUNTIME = YES
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Distribution
PROVISIONING_PROFILE_SPECIFIER = Wallnetic App Store
PRODUCT_BUNDLE_IDENTIFIER = com.wallnetic.app
MARKETING_VERSION = 1.0.0
CURRENT_PROJECT_VERSION = 1
INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.graphics-design
```

### 9.4 Info.plist

Gerekli anahtarlar:

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

**Xcode ile:**
1. Organizer'da archive secin
2. "Distribute App" tiklayin
3. "App Store Connect" secin
4. "Upload" secin
5. Signing options'i kontrol edin
6. "Upload" ile gonderin

**Transporter ile:**
1. Organizer'da "Export" secin
2. "App Store Connect" > "Export"
3. `.pkg` dosyasini kaydedin
4. Transporter app'i acin
5. `.pkg` dosyasini surukleyin
6. "Deliver" tiklayin

### 10.3 Upload Sorunlari

**Sik Karsilasilan Hatalar:**

| Hata | Cozum |
|------|-------|
| Invalid signature | Dogru sertifika kullanin |
| Missing provisioning | Profile'i yeniden olusturun |
| Invalid binary | Hardened Runtime aktif edin |
| Export compliance | Info.plist'e key ekleyin |

---

## 11. TestFlight

### 11.1 Internal Testing

1. App Store Connect > TestFlight
2. Build gorunene kadar bekleyin (5-30 dk)
3. "Internal Testing" grubuna kendinizi ekleyin
4. TestFlight app'i ile test edin

### 11.2 External Testing (Beta)

1. Build'i "External Testing" icin secin
2. Beta App Review'a gonderin (24-48 saat)
3. Onaylandiktan sonra test linkini paylasin
4. Max 10,000 tester

### 11.3 Beta Test Notu

```
Welcome to Wallnetic Beta!

What's being tested:
- AI video generation with 7 different models
- Library management and collections
- Multi-monitor support
- Theme settings

Known issues:
- Generation may take 1-3 minutes
- Some models require more credits than others

Please report bugs to: beta@wallnetic.app

Thank you for testing!
```

---

## 12. App Review Sureci

### 12.1 Review Guidelines Uyumu

**Kontrol Edilecekler:**

- [x] 4.2 Minimum Functionality - Evet, tam islevsel
- [x] 4.3 Spam - Benzersiz uygulama
- [x] 5.1.1 Data Collection - Minimum veri, privacy policy var
- [x] 5.1.2 Data Use - Sadece AI generation icin
- [x] 5.6 Developer Code of Conduct - Uygun

### 12.2 Review Notes (App Store Connect)

```
Thank you for reviewing Wallnetic!

API KEY REQUIREMENT:
This app requires a fal.ai API key to generate videos. For testing purposes, you can:

1. Sign up for free at https://fal.ai
2. Get an API key from https://fal.ai/dashboard/keys
3. Enter the key in Settings > AI tab

Or use this demo key (limited credits):
[DEMO_KEY_HERE]

TESTING THE APP:
1. Open app, go to Settings > AI
2. Enter API key and click "Validate & Save"
3. Go to "Generate" from sidebar
4. Enter a prompt like "Anime girl with flowing hair"
5. Select Kling Standard model
6. Click "Generate Video"
7. Wait 1-2 minutes for generation
8. Add to library or view in Finder

Please note that video generation requires an active internet connection and may take 1-3 minutes depending on the model selected.

If you have any questions, please contact us at review@wallnetic.app
```

### 12.3 Common Rejection Reasons

| Neden | Cozum |
|-------|-------|
| Incomplete information | Review notes'u detayli yazin |
| Bugs/crashes | TestFlight'ta iyice test edin |
| Placeholder content | Gercek icerik kullanin |
| Privacy issues | Privacy policy'yi tamamlayin |
| Guideline 4.2 | Yeterli ozellik ekleyin |

### 12.4 Review Suresi

- Ilk submission: 24-48 saat
- Resubmission: 24 saat
- Expedited review: Acil durumlar icin basvurulabilir

---

## 13. Checklist

### Pre-Submission Checklist

**Developer Account:**
- [ ] Apple Developer Program uyeligil aktif
- [ ] Apple Distribution sertifikasi olusturuldu
- [ ] Provisioning profile olusturuldu

**App Store Connect:**
- [ ] App olusturuldu
- [ ] App Information dolduruldu
- [ ] Pricing (Free) ayarlandi
- [ ] App Privacy tamamlandi

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
- [ ] Preview video (opsiyonel)

**Xcode:**
- [ ] Bundle ID dogru
- [ ] Version ve Build numaralari ayarlandi
- [ ] Signing dogru yapilandirildi
- [ ] Entitlements tamamlandi
- [ ] Info.plist tamamlandi
- [ ] Archive basariyla olusturuldu

**Testing:**
- [ ] Tum ozellikler test edildi
- [ ] Crash yok
- [ ] Memory leak yok
- [ ] Performance sorunlari yok
- [ ] TestFlight'ta test edildi

**Legal:**
- [ ] Privacy Policy yayinlandi
- [ ] Terms of Service (opsiyonel)
- [ ] Export Compliance (No encryption)

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
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [fal.ai Documentation](https://docs.fal.ai)

---

## Iletisim

Sorular icin:
- Email: support@wallnetic.app
- Website: https://wallnetic.app

---

*Bu dokuman Wallnetic v1.0.0 icin hazirlanmistir.*
*Son guncelleme: Mart 2026*
