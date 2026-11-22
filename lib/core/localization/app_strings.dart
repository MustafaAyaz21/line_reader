import 'package:flutter/material.dart';

import 'app_locale.dart';

/// Uygulama arayüzündeki Türkçe / İngilizce metin yardımcıları.
///
/// Yalnızca arayüz etiketlerini çevirir; kelime çevirileri her zaman Türkçe,
/// makale içerikleri ise orijinal dilinde kalır.
class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  bool get isEn => language == AppLanguage.en;

  static AppStrings of(BuildContext context) {
    return AppStrings(AppLocaleScope.languageOf(context));
  }

  /// Kısa iki dilli seçim yardımcısı (`tr` / `en`).
  String t(String tr, String en) => isEn ? en : tr;

  // Gezinme ve Ana Menü
  String get mainMenuTitle => t('Ana Menü', 'Home');
  String get myWordsTitle => t('Kelimelerim', 'My Words');
  String get browserTitle => t('Tarayıcı', 'Browser');
  String get browserSubtitle =>
      t('Web\'de oku ve anında çevir', 'Read on the web & translate instantly');
  String get articlesTitle => t('Makaleler', 'Articles');
  String get articlesSubtitle => t('Çevrimdışı okumalar', 'Offline readings');
  String get settingsTitle => t('Ayarlar', 'Settings');
  String get updatesTitle => t('Güncellemeler', 'Updates');
  String get newUpdateAvailable =>
      t('Yeni Güncelleme Mevcut', 'New Update Available');

  // Ortak eylemler
  String get cancel => t('İptal', 'Cancel');
  String get save => t('Kaydet', 'Save');
  String get delete => t('Sil', 'Delete');
  String get retry => t('Tekrar Dene', 'Try Again');
  String get close => t('Kapat', 'Close');
  String get signIn => t('Giriş Yap', 'Sign In');
  String get signUp => t('Kayıt Ol', 'Sign Up');
  String get signOut => t('Çıkış Yap', 'Sign Out');

  // Seviye metinleri
  String levelLabel(String code) => switch (code.toUpperCase()) {
        'A1' => t('Başlangıç', 'Beginner'),
        'A2' => t('Temel', 'Elementary'),
        'B1' => t('Orta', 'Intermediate'),
        'B2' => t('Üst Orta', 'Upper Intermediate'),
        'C1' => t('İleri', 'Advanced'),
        'C2' => t('Uzman', 'Proficiency'),
        _ => code,
      };

  String levelSubtitle(String code) => switch (code.toUpperCase()) {
        'A1' => t(
            'Temel günlük ifadeler ve kısa metinler',
            'Basic everyday phrases and short texts',
          ),
        'A2' => t(
            'Günlük yaşam ve sade anlatımlar',
            'Daily life and clear stories',
          ),
        'B1' => t(
            'Akıcı konu anlatımları ve kısa hikayeler',
            'Smooth topics and short stories',
          ),
        'B2' => t(
            'Detaylı makaleler ve yorum yazıları',
            'Detailed articles and opinion pieces',
          ),
        'C1' => t(
            'Derinlikli, zengin kelime dağarcıklı metinler',
            'In-depth texts with rich vocabulary',
          ),
        'C2' => t(
            'Edebi ve akademik düzeyde kapsamlı okumalar',
            'Literary and academic long-form readings',
          ),
        _ => '',
      };

  String articleCountLabel(int count) => isEn
      ? (count == 1 ? '1 article' : '$count articles')
      : '$count makale';

  // Okuma ekranı
  String get underlinePenTooltip =>
      t('Altını Çizme Kalemi', 'Underline Pen');
  String get underlinePenActiveTooltip =>
      t('Altını Çizme Kalemi Açık', 'Underline Pen On');
  String get underlinePenShort => t('Çiz', 'Pen');
  String get underlineBannerHint => t(
        'Çizmek için kelimeye dokunun veya seçin; kaldırmak için çizili alana tekrar dokunun.',
        'Tap or select text to underline; tap an underlined area again to remove it.',
      );
  String get readerAppearanceTooltip =>
      t('Arka Plan Tonu ve Yazı Boyutu', 'Background Tone & Font Size');
  String get readerAppearanceTitle => t('Okuma Görünümü', 'Reading Appearance');
  String get backgroundToneLabel => t('Arka Plan Tonu', 'Background Tone');
  String get fontSizeLabel => t('Yazı Boyutu', 'Font Size');
  String get toneWhite => t('Beyaz', 'White');
  String get tonePaper => t('Kağıt Tonu', 'Paper');
  String get toneDark => t('Koyu', 'Dark');
  String get underlineAction => t('Altını Çiz', 'Underline');
  String get removeUnderlineAction => t('Çizgiyi Kaldır', 'Remove Underline');
  String get removeShort => t('Kaldır', 'Remove');
  String get lookupMeaningAction => t('Anlamına Bak', 'Look Up');

  // Misafir ve Hesap
  String get guestModeTitle => t('Misafir Modu', 'Guest Mode');
  String get continueAsGuest =>
      t('Misafir Olarak Devam Et', 'Continue as Guest');
  String get continueWithGoogle =>
      t('Google (Gmail) ile Devam Et', 'Continue with Google (Gmail)');
  String guestLimitNotice(int limit) => t(
        'Misafir modunda günlük $limit kelime çeviri hakkınız vardır. Sınırsız çeviri için ücretsiz hesap oluşturun.',
        'Guest mode includes $limit word translations per day. Create a free account for unlimited translations.',
      );
  String guestQuotaRemaining(int remaining, int limit) => t(
        'Bugün kalan çeviri hakkı: $remaining / $limit',
        'Translations left today: $remaining / $limit',
      );
  String guestQuotaReachedMessage(int limit) => t(
        'Misafir olarak günlük $limit kelime çeviri hakkınız doldu. Sınırsız çeviri için ücretsiz giriş yapın veya kayıt olun.',
        'You have reached your daily guest limit of $limit word translations. Sign in or create a free account for unlimited translations.',
      );
}

extension AppStringsContextExtension on BuildContext {
  AppStrings get l10n => AppStrings.of(this);
}
