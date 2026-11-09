<p align="center">
  <img src="assets/icon/app_icon.png" width="112" alt="PureScan">
</p>

<h1 align="center">PureScan</h1>

<p align="center">
  Belgeyi tara veya PDF aç, paylaşmak istemediğin yerleri seç,<br>
  o bilgilerin içinde bulunmadığı yeni bir PDF oluştur.
</p>

---

PureScan bir Android uygulamasıdır. Örneğin bir banka belgesindeki hesap numarasını ya da bir sözleşmedeki adresi kaldırıp belgenin kalanını paylaşmak için kullanılır.

Bilginin üstüne siyah bir kutu koymak yeterli değildir: kutu kaldırılabilir, metin kopyalanabilir, dosyanın içinde eski bir katman kalabilir. PureScan seçilen bilgiyi dosyanın kendisinden çıkarır. Tüm işlem telefonda yapılır; belge, görüntü veya dosya adı hiçbir sunucuya gönderilmez.

## Nasıl çalışır

1. Her sayfa telefonda bir görüntüye dönüştürülür.
2. Seçilen alanlardaki pikseller düz siyahla **değiştirilir**. Üste kutu eklenmez; alttaki görüntü artık yoktur.
3. Seçim sınırları dışa doğru yuvarlanır ve küçük bir güvenlik payı eklenir.
4. Yalnızca bu temiz görüntülerden **sıfırdan** yeni bir PDF oluşturulur. Kaynak dosyanın metinleri, yazı tipleri, yorumları, form alanları, ekleri, betikleri, katmanları ve meta verisi yeni dosyaya taşınmaz.
5. Kaydedilen dosya paylaşılmadan önce kontrol edilir. Kontrol geçmezse dosya silinir ve paylaşım açılmaz.

Kaynak dosya hiçbir zaman değiştirilmez.

### Çıktı kontrolleri

Kontroller ekrandaki önizleme üzerinde değil, diske yazılmış son dosya üzerinde yapılır:

- Dosya, üretimde kullanılandan farklı bir PDF motoruyla (Android `PdfRenderer`) açılır; sayfa sayısı, sırası ve boyutları beklenenle karşılaştırılır.
- Dosyaya gömülü her sayfa görüntüsünün, pikselleri silinmiş temiz görüntüyle bayt bayt aynı olduğu doğrulanır. Seçilen alanların her pikseli siyah olmalıdır.
- Dosya yapısı tek tek nesne düzeyinde incelenir: metin katmanı, yazı tipi, yorum, form, ek, betik, eski sürüm, meta veri veya fazladan görüntü bulunursa dosya reddedilir.
- Paylaşım veya kaydetme anında dosyanın SHA-256 özeti yeniden hesaplanır; kontrol edilen dosya ile paylaşılan dosya aynı olmalıdır.

Bu kontroller kullanıcının yanlış veya eksik seçim yapmasını engellemez. Uygulama "belgede hassas bilgi kalmadı" gibi bir iddiada bulunmaz.

## Özellikler

- Kamerayla tek veya çok sayfalı tarama
- Telefondaki PDF ve fotoğrafları içe aktarma, şifreli PDF için şifre sorma
- Sayfa ekleme, silme, sıralama, 90° döndürme, kenar kırpma ve okunurluk iyileştirme
- Bulanık veya düşük çözünürlüklü sayfa uyarısı
- Yakınlaştırarak alan seçme; seçimleri taşıma, boyutlandırma, silme, geri ve ileri alma
- Döndürme ve kırpmadan sonra seçimlerin otomatik olarak doğru yere taşınması
- Son dosyayı önizleme, cihaza kaydetme ve paylaşma
- İnternet olmadan çalışma

## Bu yöntemin bedeli

Çıktıdaki yazılar görüntü olur. Bu yüzden yeni dosyada:

- Metin seçme, arama ve ekran okuyucuyla okuma çalışmaz.
- Doldurulabilir formlar ve etkileşimli öğeler korunmaz.
- Kaynak belgenin dijital imza doğrulaması bulunmaz.
- Dosya boyutu kaynaktan büyük olabilir.

Bu sınırlamalar dosya oluşturulmadan önce kullanıcıya gösterilir.

## Gizlilik

- Belge işleme tamamen cihazda yapılır. Uygulamanın internet izni yoktur.
- Çalışma kopyaları uygulamanın özel önbellek klasöründe tutulur; galeriye veya genel klasörlere yazılmaz.
- Uygulama verileri bulut yedeğine ve cihazdan cihaza aktarıma dahil edilmez.
- Geçici dosyalar işlem bitince veya iptal edilince silinir. Çökmeden kalanlar bir sonraki açılışta temizlenir. Paylaşım kopyası, alıcı uygulama okuyabilsin diye bir sonraki açılışta silinir.
- Kamera izni yalnızca tarama başlarken istenir. Dosya ve fotoğraf seçiminde sistem seçicileri kullanılır.
- Hata kayıtlarında belge içeriği, dosya adı veya dosya yolu bulunmaz.
- Uygulama arka plana geçtiğinde belge görünümü gizlenir.

Bilgi kaldırma, dosyayı şifrelemek değildir: paylaşılan dosyayı açan kişi kaldırılmamış bölümleri görebilir.

## Kurulum

Gereksinimler:

- Flutter 3.32 (Dart 3.8)
- Android SDK, Android 6.0 (API 23) ve üzeri bir cihaz veya emülatör

```bash
git clone https://github.com/keremsenn/pureScan.git
cd pureScan
flutter pub get
flutter run
```

APK oluşturmak için:

```bash
flutter build apk --release
```

> `pdfx` paketi `2.9.2` sürümüne sabitlenmiştir. Daha yeni sürümler Flutter 3.32 ile derlenmez.

## Testler

```bash
flutter test
```

Testler; piksel silme ve güvenlik payını, PDF içine gömülen görüntünün temizlenmiş görüntüyle aynı olduğunu, yapı incelemesinin metin, yorum, ek ve eski sürüm gibi öğeleri yakaladığını, döndürme ve kırpma sonrası seçim konumlarını ve seçim düzenleme ile geri almayı kapsar.

Bağımsız PDF motoruyla yapılan kontroller (`PdfRenderer`) yalnızca cihazda çalışır; bunlar için uygulamanın telefonda denenmesi gerekir. Testlerde gerçek belge kullanılmamalı, sahte bilgiler içeren deneme belgeleri hazırlanmalıdır.

## Proje yapısı

```
lib/
├── app/router/          Sayfa yönlendirmeleri
├── core/
│   ├── constants/       Sabitler ve kullanıcı metinleri
│   ├── security/        Gizli kayıt tutucu, geçici dosya yönetimi
│   ├── theme/           Tema
│   └── utils/           Koordinat ve dosya yardımcıları
├── features/
│   ├── home/            Ana ekran
│   ├── scanner/         Kamera ile tarama
│   ├── document_editor/ Sayfa yönetimi ve kırpma
│   ├── redaction/       Alan seçme ve son kontrol
│   ├── processing/      Dosya oluşturma ve kontrol
│   └── share/           Sonuç, kaydetme ve paylaşma
└── shared/
    ├── models/          Sayfa, seçim ve kontrol raporu
    ├── providers/       Oturum ve işlem durumu (Riverpod)
    └── services/        Görüntü temizleme, piksel silme, PDF oluşturma,
                         yapı incelemesi, çıktı kontrolü, paylaşım koruması
```

## İkon ve açılış ekranı

Kaynak görseller `assets/icon/` klasöründedir. Değiştirdikten sonra:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Sınırlar ve yapılacaklar

- Başlangıç sınırı tek belgede 50 sayfa ve 50 MB giriş dosyasıdır. Bu değerler desteklenecek cihazlarda yapılacak ölçümlerle güncellenmelidir.
- Diskteki çalışma kopyaları henüz şifrelenmiyor (Android Keystore ile şifreleme planlanıyor).
- Sayfa kenarları elle kırpılıyor; otomatik kenar bulma yok.
- Otomatik bilgi bulma (cihaz içi OCR ile IBAN, telefon, e-posta önerisi) sonraki sürüme bırakıldı.
