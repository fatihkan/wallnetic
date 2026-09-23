# Arayüz ve kod incelemesi — 23 Eylül 2026

İnceleme ana gezinme, Explore/Popular kütüphane ekranları, dosya içe aktarma ve bu ekranların kullandığı model/servislerle sınırlıdır. Mevcut SwiftUI yapısı ve tasarım tokenları korundu.

## Düzeltilen bulgular

| Öncelik | Bulgu ve etkisi | Düzeltme |
| --- | --- | --- |
| P1 | `ImportGate`, yalnızca actor olmasına güveniyordu. Bir işlem `await` sırasında askıya alındığında ikinci işlem aynı kritik bölgeye girebiliyordu. | Askıya alma noktaları boyunca tutulan izin ve bekleme kuyruğu eklendi. Hata ve iptalde izin bırakılıyor; kütüphane listesi MainActor üzerinden okunuyor. |
| P1 | Süre veya çözünürlük NaN, sonsuz ya da `Int` sınırlarının dışında olduğunda biçimlendirme uygulamayı çökertebiliyordu. | Sayısal dönüşümlerden önce geçerlilik denetleniyor; geçersiz metadata için mevcut yer tutucular gösteriliyor. |
| P2 | MOV/M4V/HEVC dosyaları dönüştürülmeden `.mp4` adıyla kopyalanıyordu. | Yerel formatın uzantısı korunuyor; gerçekten dönüştürülen dosyalar MP4 olarak kaydediliyor. Dönüşümün geçici çıktısı kopyalama sonrası temizleniyor. |
| P2 | Sürüklenen desteklenmeyen dosyalar veya video uzantılı klasörler kütüphaneye alınabiliyordu. | Ortak içe aktarma katmanında dosya türü ve normal dosya kontrolü eklendi. |
| P2 | Dosya seçici GIF/WebP gibi desteklenen bazı formatları göstermiyordu. Güvenlik kapsamı erişimi `false` dönerse içe aktarma sessizce atlanıyordu. | Seçici desteklenen uzantı listesini kullanıyor. Erişim sonucu ne olursa olsun dosya okunmaya çalışılıyor ve gerçek hata kullanıcıya gösteriliyor. |
| P2 | `maxInflight <= 0` ile toplu içe aktarma bütün girdileri sessizce düşürüyordu. | En az bir işlem çalıştırılıyor; her girdi için sonuç üretiliyor. |
| P2 | Explore ve Popular'da sol/sağ oklar aynı yönde ve görünen filtre/sıralamadan bağımsız ilerliyordu. | Her iki yön görünen liste sırasını izliyor, listenin sonunda başa dönüyor. |
| P2 | Explore, aramanın alaka sırasını kaybediyordu; Popular ad sıralaması yeniden adlandırmayı dikkate almıyordu. | Filtreler arama sırasını koruyor; ad sıralaması görünen adı ve doğal metin karşılaştırmasını kullanıyor. |
| P2 | Explore'da süresi bilinmeyen videolar “Short” filtresine giriyordu. | Bu filtre yalnızca bilinen, geçerli kısa süreleri kabul ediyor. |
| P2 | Üst menünün bağımsız üst üste yerleşen bölümleri dar pencerede arama alanıyla çakışabiliyordu. | Gezinme, arama ve eylemler tek yatay yerleşime alındı. |
| P2 | Açık temada boş kütüphane metinleri beyaz kalıyordu; filtre sonuçsuz kaldığında ekran açıklamasız boş görünüyordu. | Temaya uyumlu boş kütüphane ve sonuç bulunamadı ekranları, kaynaklara gitme ve filtre sıfırlama eylemleri eklendi. |
| P2 | Explore/Popular kartlarını uygulamak çift tıklamayı bilmeyi gerektiriyordu; liste eylemi yalnızca hover sırasında görünüyordu. | Kart görselleri etiketli düğmelere çevrildi; liste eylemi her zaman erişilebilir. Renk/görünüm filtrelerine erişilebilir adlar ve seçili durum bilgisi eklendi. |

İçe aktarma sırasında dosya sayısı ve sürükleme hedefi gösteriliyor. Explore küçük resimleri üretilemediğinde süresiz yükleme göstergesi yerine film simgesi gösteriliyor. Üst menüde sistem klavye odak göstergeleri yeniden etkin.

## Doğrulama

- Xcode 26.4, Debug, yerel arm64 macOS hedefi: **140 test geçti, 0 hata**.
- Yeni `LibraryReviewTests`: **10 test**. Eşzamanlı işlemler arasında dışlama, hata/iptal sonrası izin bırakma, geçersiz toplu işlem sınırı, dosya uzantısı ve kaynak dosyanın korunması, desteklenmeyen girdiler, tekrar içe aktarma, gezinme ve geçersiz metadata kapsanıyor.
- `xcodegen generate` çalıştırıldı; proje dosyasına yalnızca yeni testin kayıtları eklendi.
- `git diff --check` başarılı.
- Gerçek derlenmiş SwiftUI bileşenleri, AppKit `NSHostingView` üzerinden 900×600 boyutta açık/koyu temada görüntülendi. Üst menü ve boş kütüphane yerleşimi incelendi. Bu kontrol tüm uygulamanın etkileşimli UI testi değildir.

Test komutu:

```sh
xcodebuild test \
  -project src/Wallnetic/Wallnetic.xcodeproj \
  -scheme Wallnetic \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/wallnetic-review-build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_ENTITLEMENTS= ENABLE_APP_SANDBOX=NO \
  DEBUG_INFORMATION_FORMAT=dwarf
```

Yerel testte CI ile aynı imzalama/sandbox ayarları kullanıldı. İmzalı App Store sandbox davranışı, gerçek medya dönüştürme, VoiceOver ile uçtan uca gezinme, Intel ve macOS 13 ayrıca çalıştırılmadı.

## Kalan inceleme notları

- `SlideshowGenerator.swift:90`: MainActor üzerindeki `PhotosLibraryService.shared` varsayılan parametresi Swift 6 dil modunda hata olacak bir uyarı üretiyor.
- `VideoTrimmer.swift:47` ve `WallpaperMetadataCache.swift:275`: Sendable olmayan değerlerin eşzamanlı closure'larda yakalanması için derleyici uyarıları var. Bunlar ayrı bir actor izolasyonu incelemesi gerektiriyor; bu çalışmada çalışma zamanı yarışı kanıtlanmadı.
- XcodeGen'in ortak widget model klasörünü birden fazla gruba koymasına ilişkin proje uyarısı devam ediyor. Derleme ve testleri engellemiyor.
- Kullanıcının mevcut `docs/SOCIAL_MEDIA.md` ve `scripts/` değişikliklerine müdahale edilmedi.

## İkinci tur — ana sayfa, galeri ve ayarlar

İlk turun PR #239 ile `dev` içine alınmasının ardından, `fix/home-gallery-review` branch'inde devam edildi.

| Bulgu | Düzeltme |
| --- | --- |
| Ana sayfa seçiminde dizi indeksi kullanılıyordu. Silme veya sıralama değişikliği, başka başlıkla eski görselin eşleşmesine ya da ana görselin boş kalmasına yol açabiliyordu. | Seçim UUID üzerinden çözülüyor; seçilen öğe artık yoksa ilk geçerli öğeye dönülüyor. Görsel görevleri de duvar kâğıdı kimliğine bağlı. |
| Ana başlık, kullanıcının verdiği özel ad yerine orijinal dosya adını gösteriyordu. | `displayName` kullanılıyor; favori ve oynatma/duraklatma durumları da açıkça gösteriliyor. |
| Otomatik ana görsel geçişi durdurulamıyor ve Hareketi Azalt tercihini dikkate almıyordu. | Önceki/sonraki, doğrudan seçim ve duraklatma kontrolleri eklendi. Kullanıcı gezinmesi otomatik geçişi durduruyor; hover, pasif uygulama ve Hareketi Azalt durumunda geçiş yapılmıyor. Görünüme bağlı iptal edilebilir görev, eski Timer'ın yerini aldı. |
| Ana sayfa kartları çift tıklama, 3D galeri dış katmanı tek tıklama bekliyordu. | Tek, erişilebilir düğme eylemi kullanılıyor; galeri callback'i aynı düğmeden çağrılıyor. |
| Kart parlamasında hover yokken negatif ve sırasız gradient durakları oluşuyordu. | Parlama merkezi 0…1 aralığında tutuluyor. Hover dönüşleri ve galeri perspektifi Hareketi Azalt tercihinde devre dışı. |
| Küçük resimlerin NSImage boyutu, çözümlenen karenin ölçüsü yerine istenen sınırlayıcı kutuya atanıyordu; dikey/kare videolar geriliyordu. | Görüntünün gerçek piksel ölçüsü korunuyor. Yerleşim kırpmasını SwiftUI yapıyor. |
| Ana sayfa kartları başarısız küçük resim üretiminde süresiz yükleniyor görünüyordu. | Yükleme ve başarısız önizleme durumları ayrıldı. |
| Tema seçenekleri yalnızca tap gesture ile çalışıyordu; ayarların seçili simgeleri açık temada beyaz kalıyordu. | Tema satırları erişilebilir düğmelere çevrildi; ayar simgeleri temaya uyumlu ve klavye odak göstergeleri etkin. |
| Oturum açınca başlat anahtarı hatada yanlış durumda kalıyordu. Ayarlar açılırken durum okumak da gereksiz kayıt işlemi tetikleyebiliyordu. | Sistem durumu ile kullanıcı eylemi ayrıldı. Hata gösteriliyor, anahtar gerçek durumla eşitleniyor; sistem onayı gerektiğinde Login Items bağlantısı sunuluyor. |

Galeri derinlik hesabı tek kaydırma ölçümüne alındı; katman sırası doğrudan kardeş kartlara uygulanıyor. Görsel inceleme sırasında AppKit bitmap yakalamasında görülen 3D kart yığılması, gerçek pencere ekran görüntüsüyle karşılaştırılarak yakalama aracına ait bir sorun olarak ayrıştırıldı.

Doğrulama: **168 test geçti, 0 hata**; bu turda **7 yeni test** eklendi. Dikey, kare ve yatay H.264 test videoları çalışma sırasında oluşturulup gerçek AVFoundation küçük resim hattından geçirildi. Ana sayfa/tema ayarları açık-koyu görünümde, galeri ise gerçek pencere görüntüleriyle kontrol edildi. Görsel kontrol verileri `/tmp` altındaki ayrı uygulama alanında tutuldu.

Gerçek oturum açma kaydı değiştirilmedi; sistem onayı gerektiren akış imzalı dağıtım üzerinde uçtan uca denenmedi. Bu tur için GitHub CI çalıştırılmadı.
