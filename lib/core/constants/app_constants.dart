class AppConstants {
  AppConstants._();

  static const String appName = 'PureScan';
  static const String appTagline = 'Kalıcı Bilgi Kaldırma ve Belge Tarayıcı';

  static const String defaultOutputFileName = 'belge_temizlenmis.pdf';

  static const int redactionSecurityMarginPx = 6;

  static const double defaultRenderDpi = 200.0;

  static const int maxPages = 50;
  static const int maxInputFileMb = 50;

  static const String permanentRedactionWarning =
      'Yeni dosyada seçtiğiniz alanlar kalıcı olarak kaldırılacak. '
      'Orijinal belgeniz değişmeyecek. '
      'Yeni dosyanın içinden bu bilgileri geri getiremezsiniz.';

  static const String postVerificationAdvisory =
      'Seçtiğiniz alanlar kaldırıldı. '
      'Paylaşmadan önce belgenin kalanını kontrol edin.';

  static const String rasterizationTradeOffNotice =
      'Yeni dosyadaki yazılar görüntü olur: metin seçme, arama ve ekran '
      'okuyucuyla okuma çalışmaz. Dosya büyüyebilir. Doldurulabilir formlar ve '
      'etkileşimli öğeler korunmaz. Yeni kopya, kaynak belgenin dijital imza '
      'doğrulamasını taşımaz. Bu dosya orijinalin aynı özelliklere sahip bir kopyası değildir.';
}
