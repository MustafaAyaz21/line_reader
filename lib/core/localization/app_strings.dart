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
  String get continueReadingTitle =>
      t('Kaldığın yerden devam et', 'Continue where you left off');
  String readingProgressPercent(int percent) =>
      isEn ? '$percent%' : '%$percent';
  String readingProgressCompletedLabel(int percent) => percent >= 100
      ? t('Tamamlandı', 'Completed')
      : t('%$percent tamamlandı', '$percent% completed');
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
  String newArticlesAvailableLabel(int count) => isEn
      ? (count == 1 ? '+1 new article loaded' : '+$count new articles loaded')
      : '+$count yeni makale yüklendi';
  String newLevelArticlesAvailableLabel(int count, String levelCode) => isEn
      ? (count == 1
          ? '+1 new $levelCode article loaded'
          : '+$count new $levelCode articles loaded')
      : '+$count yeni $levelCode makalesi yüklendi';
  String get refreshAction => t('Yenile', 'Refresh');

  // Okuma ekranı
  String get underlinePenTooltip =>
      t('Altını Çizme Kalemi', 'Underline Pen');
  String get underlinePenActiveTooltip =>
      t('Altını Çizme Kalemi Açık', 'Underline Pen On');
  String get underlinePenShort => t('Çiz', 'Pen');
  String get underlineBannerHint => t(
        'Basılı tutup sürükleyerek kelimeleri çizin; çizili kelimeye tek tıkla çizgiyi kaldırın.',
        'Press and drag across words to mark; tap a marked word once to remove it.',
      );
  String get readerAppearanceTooltip =>
      t('Görünüm, Yazı Boyutu ve İşaretleme', 'Appearance, Font & Markup');
  String get readerAppearanceTitle => t('Okuma Görünümü', 'Reading Appearance');
  String get backgroundToneLabel => t('Arka Plan Tonu', 'Background Tone');
  String get fontSizeLabel => t('Yazı Boyutu', 'Font Size');
  String get markStyleLabel => t('İşaretleme Stili', 'Markup Style');
  String get markColorLabel => t('İşaretleme Rengi', 'Markup Color');
  String get markStyleUnderline => t('Altı Çizili', 'Underline');
  String get markStyleHighlight => t('Fosforlu Kalem', 'Highlighter');
  String get markStyleStrikethrough => t('Üstü Çizili', 'Strikethrough');
  String get toneTheme => t('Tema', 'Theme');
  String get toneWhite => t('Beyaz', 'White');
  String get tonePaper => t('Kağıt Tonu', 'Paper');
  String get toneDark => t('Koyu', 'Dark');
  String get underlineAction => t('Altını Çiz', 'Underline');
  String get removeUnderlineAction => t('Çizgiyi Kaldır', 'Remove Underline');
  String get removeShort => t('Kaldır', 'Remove');
  String get lookupMeaningAction => t('Anlamına Bak', 'Look Up');
  String get translateSelectionAction => t('Çevir', 'Translate');
  String get translateParagraphAction =>
      t('Paragrafı Çevir', 'Translate Paragraph');
  String get sentenceTranslationTitle =>
      t('Cümle Çevirisi', 'Sentence Translation');
  String get paragraphTranslationTitle =>
      t('Paragraf Çevirisi', 'Paragraph Translation');
  String get presetTranslationBadge => t('Hazır Çeviri', 'Prepared');
  String get liveTranslationBadge => t('Çeviri', 'Translation');
  String get listenArticleTooltip => t('Makaleyi Sesli Dinle', 'Listen to Article');
  String get podcastAiLabel => t('Podcast AI', 'Podcast AI');
  String get deviceVoiceLabel => t('Cihaz Sesi', 'Device Voice');
  String get previousSentenceTooltip => t('Önceki Cümle', 'Previous Sentence');
  String get nextSentenceTooltip => t('Sonraki Cümle', 'Next Sentence');
  String get previousParagraphTooltip => t('Önceki Paragraf', 'Previous Paragraph');
  String get nextParagraphTooltip => t('Sonraki Paragraf', 'Next Paragraph');
  String audioPositionLabel(int paragraph, int totalParagraphs, int sentence, int totalSentences) =>
      t(
        'Paragraf $paragraph/$totalParagraphs • Cümle $sentence/$totalSentences',
        'Paragraph $paragraph/$totalParagraphs • Sentence $sentence/$totalSentences',
      );

  // Misafir, Hesap, Kod ve Zorunlu Güncelleme
  String get guestModeTitle => t('Misafir Modu', 'Guest Mode');
  String get standardAccountTitle => t('Standart Hesap', 'Standard Account');
  String get unlimitedAccountBadge =>
      t('Sınırsız Hesap (Yetkili)', 'Unlimited Account');
  String get continueAsGuest =>
      t('Misafir Olarak Devam Et', 'Continue as Guest');
  String get continueWithGoogle =>
      t('Google (Gmail) ile Devam Et', 'Continue with Google (Gmail)');
  String get redeemCodeTitle => t('Kod Kullan', 'Redeem Code');
  String get redeemCodeApply => t('Kodu Uygula', 'Apply Code');
  String get redeemCodeHint => t('Örn: READER2026', 'e.g. READER2026');
  String get mandatoryUpdateTitle => t('Zorunlu Güncelleme', 'Update Required');
  String mandatoryUpdateSubtitle(String latestVersion) => t(
        'Line Reader\'ı kullanmaya devam etmek için lütfen v$latestVersion sürümüne güncelleyin.',
        'Please update to Line Reader v$latestVersion to continue using the app.',
      );
  String guestLimitNotice(int limit) => t(
        'Misafir modunda günlük $limit kelime çeviri hakkınız vardır. Ücretsiz kayıt ile günlük 80 kelimeye çıkarın, aktivasyon kodu ile sınırsız ve reklamsız kullanın.',
        'Guest mode includes $limit word translations per day. Sign up free for 80 words/day, or redeem a code for unlimited ad-free access.',
      );
  String guestQuotaRemaining(int remaining, int limit) => t(
        'Bugün kalan çeviri hakkı: $remaining / $limit',
        'Translations left today: $remaining / $limit',
      );
  String guestQuotaReachedMessage(int limit) => t(
        'Misafir olarak günlük $limit kelime çeviri hakkınız doldu. Günlük 80 kelime hakkı için ücretsiz giriş yapın veya kayıt olun.',
        'You have reached your daily guest limit of $limit word translations. Sign in or create a free account for 80 words/day.',
      );
  String standardQuotaReachedMessage(int limit) => t(
        'Standart hesap günlük $limit kelime çeviri hakkınız doldu. Sınırsız çeviri, reklamsız kullanım ve tarayıcı AI özelliği için aktivasyon kodunuzu girebilirsiniz.',
        'You have reached your daily standard limit of $limit word translations. Redeem an activation code for unlimited ad-free translations and Browser AI.',
      );
}

extension AppStringsContextExtension on BuildContext {
  AppStrings get l10n => AppStrings.of(this);
}
