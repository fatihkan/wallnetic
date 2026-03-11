# Wallnetic Development Roadmap

> Detaylı geliştirme planı ve task listesi

## Overview

Bu doküman Wallnetic projesinin tüm geliştirme aşamalarını, task'larını ve milestone'larını içerir.

---

## Phase 0: Hazırlık ve Öğrenme

### 0.1 Swift Öğrenme (Tahmini: 2-3 hafta)

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 0.1.1 | Swift Basics - Variables, Types, Functions | P0 | ⬜ |
| 0.1.2 | Swift Basics - Control Flow, Collections | P0 | ⬜ |
| 0.1.3 | Swift OOP - Classes, Structs, Protocols | P0 | ⬜ |
| 0.1.4 | SwiftUI Fundamentals - Views, Modifiers | P0 | ⬜ |
| 0.1.5 | SwiftUI - State Management (@State, @Binding) | P0 | ⬜ |
| 0.1.6 | SwiftUI - Navigation & App Structure | P0 | ⬜ |
| 0.1.7 | macOS Specific - AppKit basics | P1 | ⬜ |
| 0.1.8 | macOS Specific - Menu bar apps | P1 | ⬜ |
| 0.1.9 | Mini Project - Basit bir macOS app yap | P0 | ⬜ |

### 0.2 Geliştirme Ortamı

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 0.2.1 | Xcode 15+ kurulumu | P0 | ⬜ |
| 0.2.2 | Apple Developer hesabı oluştur | P1 | ⬜ |
| 0.2.3 | Git repository setup | P0 | ⬜ |
| 0.2.4 | GitHub Projects board oluştur | P0 | ⬜ |
| 0.2.5 | CI/CD pipeline (GitHub Actions) | P2 | ⬜ |

### 0.3 Araştırma

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 0.3.1 | ScreenSaver.framework dokümantasyonu oku | P0 | ⬜ |
| 0.3.2 | Metal framework araştır | P1 | ⬜ |
| 0.3.3 | Açık kaynak projeleri incele (Equinox, ScreenPlay) | P0 | ⬜ |
| 0.3.4 | Rakip uygulamaları test et (Backdrop, WallMotion) | P1 | ⬜ |
| 0.3.5 | AI API'lerini test et (Replicate, fal.ai) | P1 | ⬜ |

---

## Phase 1: MVP - Temel Live Wallpaper

> Hedef: Video dosyalarını masaüstü arka planı olarak oynatabilme

### 1.1 Proje Kurulumu

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 1.1.1 | Xcode projesi oluştur (macOS App template) | P0 | ✅ |
| 1.1.2 | Proje yapısını organize et (MVVM) | P0 | ✅ |
| 1.1.3 | SwiftLint/SwiftFormat ekle | P2 | ⬜ |
| 1.1.4 | App icon ve temel assets | P1 | ✅ |

### 1.2 Wallpaper Engine Core

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 1.2.1 | ScreenSaver.framework entegrasyonu araştır | P0 | ✅ |
| 1.2.2 | Desktop window layer oluştur | P0 | ✅ |
| 1.2.3 | Video player (AVFoundation) entegre et | P0 | ✅ |
| 1.2.4 | Video loop ve playback kontrolleri | P0 | ✅ |
| 1.2.5 | Farklı video formatlarını destekle (MP4, MOV, HEVC) | P1 | ✅ |
| 1.2.6 | Performans optimizasyonu - CPU kullanımı | P0 | ✅ |
| 1.2.7 | Metal rendering pipeline | P1 | ✅ |

### 1.3 Kullanıcı Arayüzü (v1)

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 1.3.1 | Ana pencere tasarımı (SwiftUI) | P0 | ✅ |
| 1.3.2 | Video seçme/import özelliği | P0 | ✅ |
| 1.3.3 | Wallpaper önizleme (thumbnail) | P1 | ✅ |
| 1.3.4 | Play/Pause/Stop kontrolleri | P0 | ✅ |
| 1.3.5 | Menu bar app (background running) | P0 | ✅ |
| 1.3.6 | System Preferences entegrasyonu | P2 | ⬜ |

### 1.4 Multi-Monitor Desteği

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 1.4.1 | Birden fazla ekran algılama | P1 | ✅ |
| 1.4.2 | Her ekrana farklı wallpaper atama | P1 | ✅ |
| 1.4.3 | Ekran ekleme/çıkarma handling | P2 | ✅ |

### 1.5 Sistem Entegrasyonu

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 1.5.1 | Login'de otomatik başlatma | P0 | ✅ |
| 1.5.2 | Pil modunda otomatik duraklatma | P0 | ✅ |
| 1.5.3 | Tam ekran uygulama algılama (pause) | P1 | ✅ |
| 1.5.4 | Memory leak kontrolü ve optimizasyon | P0 | ✅ |

### 1.6 MVP Test & Release

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 1.6.1 | Internal testing (Alpha) | P0 | ✅ |
| 1.6.2 | Bug fixes | P0 | ✅ |
| 1.6.3 | TestFlight beta release | P1 | ✅ |
| 1.6.4 | App Store submission | P1 | ✅ |

---

## Phase 2: AI Entegrasyonu - Statik Görsel

> Hedef: Kullanıcının fotoğrafından AI ile wallpaper oluşturma

### 2.1 Backend Kurulumu

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 2.1.1 | Supabase projesi oluştur | P0 | ⬜ |
| 2.1.2 | User authentication (Apple Sign In) | P0 | ⬜ |
| 2.1.3 | Database schema tasarımı | P0 | ⬜ |
| 2.1.4 | Edge Functions - AI proxy | P0 | ⬜ |
| 2.1.5 | Image storage (Supabase Storage / R2) | P0 | ⬜ |

### 2.2 AI API Entegrasyonu

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 2.2.1 | Replicate/fal.ai hesabı ve API key | P0 | ⬜ |
| 2.2.2 | Stable Diffusion API wrapper | P0 | ⬜ |
| 2.2.3 | Text-to-image endpoint | P0 | ⬜ |
| 2.2.4 | Image-to-image (style transfer) endpoint | P0 | ⬜ |
| 2.2.5 | API rate limiting ve error handling | P1 | ⬜ |
| 2.2.6 | Caching layer (tekrar üretimi önle) | P2 | ⬜ |

### 2.3 AI Özellikleri

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 2.3.1 | Fotoğraf yükleme UI | P0 | ⬜ |
| 2.3.2 | Stil seçim arayüzü (Anime, Realistic, Abstract, etc.) | P0 | ⬜ |
| 2.3.3 | Text prompt input | P0 | ⬜ |
| 2.3.4 | Generation progress indicator | P0 | ⬜ |
| 2.3.5 | Sonuç önizleme ve kaydetme | P0 | ⬜ |
| 2.3.6 | Generation history | P1 | ⬜ |
| 2.3.7 | Favorite/koleksiyon sistemi | P2 | ⬜ |

### 2.4 Ekran Boyutu Optimizasyonu

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 2.4.1 | Otomatik ekran boyutu algılama | P0 | ⬜ |
| 2.4.2 | AI generation'da doğru aspect ratio | P0 | ⬜ |
| 2.4.3 | Retina/HiDPI desteği | P1 | ⬜ |
| 2.4.4 | Upscaling (düşük çözünürlük → yüksek) | P2 | ⬜ |

### 2.5 Lock Screen Desteği (macOS 14+)

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 2.5.1 | Lock Screen API araştırması | P1 | ⬜ |
| 2.5.2 | Lock Screen wallpaper ayarlama | P1 | ⬜ |
| 2.5.3 | Desktop + Lock Screen sync | P2 | ⬜ |

---

## Phase 3: Hareketli AI Wallpaper

> Hedef: Statik görsellerden hareketli wallpaper oluşturma

### 3.1 AI Video Generation

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 3.1.1 | Pika / Runway API araştırması | P0 | ⬜ |
| 3.1.2 | Image-to-video API entegrasyonu | P0 | ⬜ |
| 3.1.3 | Video generation UI | P0 | ⬜ |
| 3.1.4 | Progress tracking (video gen uzun sürer) | P0 | ⬜ |
| 3.1.5 | Video kalite seçenekleri | P1 | ⬜ |
| 3.1.6 | Loop-friendly video generation | P1 | ⬜ |

### 3.2 Ambient Animasyonlar

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 3.2.1 | Parallax efekti (mouse movement) | P2 | ⬜ |
| 3.2.2 | Particle sistemleri (kar, yağmur, vb.) | P2 | ⬜ |
| 3.2.3 | Gündüz/gece döngüsü | P2 | ⬜ |
| 3.2.4 | Audio-reactive animasyonlar | P3 | ⬜ |

### 3.3 Video İşleme

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 3.3.1 | Video trimming/cropping | P1 | ⬜ |
| 3.3.2 | Video loop noktası ayarlama | P1 | ⬜ |
| 3.3.3 | Video export (paylaşım için) | P2 | ⬜ |

---

## Phase 4: Monetization & Distribution

> Hedef: App Store release ve gelir modeli

### 4.1 Ödeme Sistemi

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 4.1.1 | RevenueCat entegrasyonu | P0 | ⬜ |
| 4.1.2 | Subscription planları tanımla | P0 | ⬜ |
| 4.1.3 | Free tier limitleri | P0 | ⬜ |
| 4.1.4 | Paywall UI | P0 | ⬜ |
| 4.1.5 | Restore purchases | P0 | ⬜ |
| 4.1.6 | Trial period | P1 | ⬜ |

### 4.2 App Store Hazırlık

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 4.2.1 | App Store Connect hesabı | P0 | ⬜ |
| 4.2.2 | App Store screenshots | P0 | ⬜ |
| 4.2.3 | App description & keywords (ASO) | P0 | ⬜ |
| 4.2.4 | Privacy Policy | P0 | ⬜ |
| 4.2.5 | Terms of Service | P0 | ⬜ |
| 4.2.6 | App Review guidelines kontrolü | P0 | ⬜ |
| 4.2.7 | Notarization | P0 | ⬜ |

### 4.3 Launch

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 4.3.1 | Beta testing (TestFlight) | P0 | ⬜ |
| 4.3.2 | Bug fixes from beta | P0 | ⬜ |
| 4.3.3 | App Store submission | P0 | ⬜ |
| 4.3.4 | Launch marketing (Product Hunt, Reddit) | P1 | ⬜ |
| 4.3.5 | Press kit hazırla | P2 | ⬜ |

---

## Phase 5: Community & Marketplace (Gelecek)

> Hedef: Kullanıcı içerik platformu

### 5.1 Sosyal Özellikler

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 5.1.1 | Kullanıcı profilleri | P2 | ⬜ |
| 5.1.2 | Wallpaper paylaşımı | P2 | ⬜ |
| 5.1.3 | Like/favorite sistemi | P2 | ⬜ |
| 5.1.4 | Trending wallpapers | P2 | ⬜ |

### 5.2 Marketplace

| # | Task | Öncelik | Durum |
|---|------|---------|-------|
| 5.2.1 | Creator program | P3 | ⬜ |
| 5.2.2 | Premium content satışı | P3 | ⬜ |
| 5.2.3 | Revenue sharing | P3 | ⬜ |

---

## Milestones

| Milestone | Hedef Tarih | Durum |
|-----------|-------------|-------|
| Phase 0 Complete (Swift öğrenme) | - | ✅ |
| Phase 1 MVP Alpha | - | ✅ |
| Phase 1 MVP Beta & App Store | 10 Mart 2026 | ✅ |
| Phase 2 AI Integration | 🔄 In Progress | 🔄 |
| Phase 3 Motion | - | ⬜ |
| Phase 4 Monetization | - | ⬜ |

---

## Legend

- ⬜ Not Started
- 🔄 In Progress
- ✅ Complete
- ❌ Blocked
- P0 = Critical
- P1 = High
- P2 = Medium
- P3 = Low/Nice to have
