import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_backdrop.dart';

/// Uygulamanın tüm özelliklerini yeni ve mevcut kullanıcılara sade,
/// adım adım ve görsel ikonlarla açıklayan "Nasıl Kullanılır?" rehberi.
class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visuals = AppThemeVisuals.of(context);

    final sections = <_GuideItem>[
      _GuideItem(
        icon: Icons.devices_rounded,
        iconBg: colorScheme.surfaceContainerHighest,
        iconColor: colorScheme.primary,
        title: s.t(
          'Tüm Cihazlarda Eşitlenmiş Kütüphane (Web & Mobil)',
          'Cross-Device Library (Web, Tablet & Mobile)',
        ),
        summary: s.t(
          'Bilgisayar, tablet veya telefon; dilediğin tarayıcıdan kesintisiz devam et.',
          'Read seamlessly on PC, tablet, or phone from any supported browser.',
        ),
        steps: <String>[
          s.t(
            'Bilgisayarından, tabletinden veya destekleyen herhangi bir cihazından getlinereader.com adresine git.',
            'Visit getlinereader.com on your PC, tablet, or any supported web browser.',
          ),
          s.t(
            'Mobil uygulamada kullandığın hesabınla (Google veya E-posta) giriş yap.',
            'Sign in using the same account (Google or Email) you use on your mobile device.',
          ),
          s.t(
            'Telefonda kaydettiğin tüm kelime listelerin, kelimelerin ve okuyup bitirdiğin makalelerin ("Tamamlandı" rozetleriyle birlikte) anında tarayıcında karşına gelir.',
            'All your saved vocabulary, custom word lists, and completed articles (with "Completed" badges) sync instantly in your browser.',
          ),
        ],
        tip: s.t(
          'Büyük ekranda rahatça okuyup çalışabilir, yoldayken telefondan kaldığın yerden devam edebilirsin. Kütüphanen daima seninle.',
          'Enjoy reading on a large screen at home or office, and pick up right where you left off on your phone. Your library is always with you.',
        ),
      ),
      _GuideItem(
        icon: Icons.menu_book_rounded,
        iconBg: colorScheme.primaryContainer,
        iconColor: colorScheme.onPrimaryContainer,
        title: s.t('Makaleler & Anında Çeviri', 'Articles & Instant Translation'),
        summary: s.t(
          'A1–C2 seviyeli metinlerde tek dokunuşla bağlama özel anlam gör.',
          'Tap any word in A1–C2 graded texts for exact contextual meaning.',
        ),
        steps: <String>[
          s.t(
            'Ana menüden "Makaleler"e girip İngilizce seviyeni (A1–C2) seç.',
            'Open "Articles" from Home and pick your English level (A1–C2).',
          ),
          s.t(
            'Bilmediğin bir kelimeye tek dokunduğunda o cümledeki gerçek anlamı, eş/zıt anlamlıları ve US/UK okunuşu açılır.',
            'Tap any word to see its exact meaning in that sentence, synonyms/antonyms, and US/UK IPA.',
          ),
          s.t(
            'Bir cümleyi veya paragrafı seçip "Çevir"e basarak tam çevirisini gör; kalem ikonuyla önemli yerlerin altını çiz.',
            'Select a sentence or paragraph to translate it in full; use the pen icon to highlight key parts.',
          ),
        ],
        tip: s.t(
          'Yarım bıraktığın makaleler Ana Menüde "Kaldığın yerden devam et" kartında görünür; bitirdiklerin "Tamamlandı" olarak işaretlenir.',
          'Unfinished articles appear on Home under "Continue where you left off", and finished ones get a "Completed" badge.',
        ),
      ),
      _GuideItem(
        icon: Icons.headphones_rounded,
        iconBg: colorScheme.secondaryContainer,
        iconColor: colorScheme.onSecondaryContainer,
        title: s.t('Podcast AI & Sesli Okuma', 'Podcast AI & Audio Reading'),
        summary: s.t(
          'Makaleleri doğal podcast sesiyle veya cihaz sesiyle dinle.',
          'Listen with natural Podcast AI voice or offline device speech.',
        ),
        steps: <String>[
          s.t(
            'Makale içindeyken üst çubuktaki ses dalgası / kulaklık ikonuna dokun.',
            'Tap the audio icon in the top bar while reading an article.',
          ),
          s.t(
            'Oynatıcıdan 0.75x–1.5x hız seçebilir, cümle veya paragraf atlayabilirsin.',
            'Adjust playback speed (0.75x–1.5x) and jump between sentences or paragraphs.',
          ),
          s.t(
            'Sol alttaki "Podcast AI" etiketine dokunarak istersen Cihaz Sesi (çevrimdışı) moduna geçebilirsin.',
            'Tap the "Podcast AI" pill on the bottom left to switch to offline Device TTS anytime.',
          ),
        ],
        tip: s.t(
          'Hem okuyup hem dinlemek telaffuzunu ve dinleme anlamanı iki kat hızlı geliştirir.',
          'Reading while listening boosts both pronunciation and listening comprehension.',
        ),
      ),
      if (!kIsWeb)
        _GuideItem(
          icon: Icons.manage_search_rounded,
          iconBg: colorScheme.tertiaryContainer,
          iconColor: colorScheme.onTertiaryContainer,
          title: s.t('"Line\'da Bak" (Diğer Uygulamalarda)', '"Quick Lookup" Everywhere'),
          summary: s.t(
            'WhatsApp, Instagram, Chrome veya PDF\'ten çıkmadan kelime çevir.',
            'Translate words inside any app without switching screens.',
          ),
          steps: <String>[
            s.t(
              'Telefonundaki herhangi bir uygulamada İngilizce bir kelimeye veya cümleye basılı tutup seç.',
              'Long-press and select any English word or sentence in any app on your phone.',
            ),
            s.t(
              'Açılan menüden "Line\'da Bak" seçeneğine dokun (gerekirse üç nokta menüsünden bul).',
              'Choose "Line\'da Bak" from the floating text menu (or under the three-dots menu).',
            ),
            s.t(
              'Ekranın üzerinde açılan mini kartta anlamını anında gör ve tek dokunuşla kendi kelime listene kaydet.',
              'Read the meaning in the floating mini card and save it straight to your word list.',
            ),
          ],
          tip: s.t(
            'Ayarlar → "Line\'da Bak" bölümünden mini kartta IPA, eş/zıt anlam, ses veya kaydet çubuğunun görünüp görünmeyeceğini özelleştirebilirsin.',
            'Customize what appears in the mini card under Settings → Quick Lookup.',
          ),
        ),
      _GuideItem(
        icon: Icons.public_rounded,
        iconBg: colorScheme.primaryContainer.withAlpha(210),
        iconColor: colorScheme.onPrimaryContainer,
        title: s.t('Dahili Akıllı Tarayıcı', 'Built-in Smart Browser'),
        summary: s.t(
          'İstediğin yabancı web sitesini aç ve sayfa içinde anında çevir.',
          'Browse any English website and translate words right on the page.',
        ),
        steps: <String>[
          s.t(
            'Ana Menüden "Tarayıcı"ya girip adres çubuğuna bir site yaz veya arama yap.',
            'Open "Browser" from Home and visit any English article, blog, or news site.',
          ),
          s.t(
            'Sayfa içindeki herhangi bir kelimeye dokunarak anlamını gör ve kelime defterine ekle.',
            'Tap any word on the page to translate it instantly and save it to your lists.',
          ),
        ],
        tip: s.t(
          'Premium hesaplarda tarayıcı çevirisi cümle bağlamını analiz eden yapay zekâ desteğiyle çalışır.',
          'Premium accounts unlock context-aware AI translation inside the browser.',
        ),
      ),
      _GuideItem(
        icon: Icons.bookmark_border_rounded,
        iconBg: colorScheme.secondaryContainer.withAlpha(210),
        iconColor: colorScheme.onSecondaryContainer,
        title: s.t('Kelimelerim & Akıllı Arama', 'My Words & Smart Search'),
        summary: s.t(
          'Kelimeleri listelerde biriktir, uzun örnek cümlelerle pekiştir.',
          'Organize saved words into lists and search with real example sentences.',
        ),
        steps: <String>[
          s.t(
            'Alt menüden "Kelimelerim" sekmesine geç ve istediğin kadar renkli liste oluştur.',
            'Open "My Words" from the bottom bar and create custom color-coded lists.',
          ),
          s.t(
            'Üstteki arama çubuğuna herhangi bir İngilizce kelime veya kalıp (örn. "air transport") yazıp kapsamlı anlamlarını ve uzun örnek cümlelerini gör.',
            'Use the top search bar to look up any word or phrase with rich meanings and full example sentences.',
          ),
          s.t(
            'Yanlış yazsan bile sistem "Bunu mu aratmak istediniz?" önerisiyle doğru kelimeyi tek dokunuşta getirir.',
            'Misspelled words automatically show "Did you mean" suggestions.',
          ),
        ],
        tip: s.t(
          'Kaydettiğin her kelimenin üzerine dokunarak tüm anlamlarını, örneklerini ve sesli telaffuzunu tekrar edebilirsin.',
          'Tap any saved word card to expand all meanings, synonyms, and audio.',
        ),
      ),
      _GuideItem(
        icon: Icons.palette_outlined,
        iconBg: colorScheme.tertiaryContainer.withAlpha(210),
        iconColor: colorScheme.onTertiaryContainer,
        title: s.t('Temalar & Kişiselleştirme', 'Themes & Personalization'),
        summary: s.t(
          'Telefonun karanlık moduna uyumlu 5 tema ve esnek görünüm ayarları.',
          '5 themes with automatic system dark/light mode and flexible display options.',
        ),
        steps: <String>[
          s.t(
            kIsWeb
              ? 'Ayarlar → "Görünüm ve Temalar"dan web dilini (Türkçe/English) ve 5 temadan dilediğini seç.'
              : 'Ayarlar → "Görünüm ve Temalar"dan uygulama dilini (Türkçe/English) ve 5 temadan dilediğini seç.',
            'Change interface language and pick from 5 themes in Settings → Appearance & Themes.',
          ),
          s.t(
            'Ayarlar → "Özellikler"den IPA\'yı (US+UK / Sadece US / Sadece UK / Kapalı), eş ve zıt anlamları dilediğin gibi ayarla.',
            'Adjust IPA display mode and synonym/antonym visibility in Settings → Features.',
          ),
        ],
        tip: s.t(
          '"Varsayılan" tema, telefonunun karanlık veya açık moduna otomatik olarak uyum sağlar.',
          'The "Classic" theme automatically matches your phone\'s dark or light mode.',
        ),
      ),
    ];

    return AppThemeBackdrop(
      child: Scaffold(
        backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
        appBar: AppBar(
          title: Text(s.t('Nasıl Kullanılır?', 'How to Use')),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(110),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: colorScheme.primary.withAlpha(60),
                ),
              ),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: colorScheme.primary,
                    child: Icon(
                      Icons.lightbulb_outline_rounded,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          s.t(
                            'Line Reader Hızlı Rehber',
                            'Line Reader Quick Guide',
                          ),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          s.t(
                            'Merak ettiğin özelliğe dokun, 10 saniyede nasıl kullanıldığını gör.',
                            'Tap any feature below to see how it works in seconds.',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...sections.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: index == 0,
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: item.iconBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(item.icon, color: item.iconColor, size: 21),
                      ),
                      title: Text(
                        item.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        item.summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      children: <Widget>[
                        const SizedBox(height: 4),
                        ...item.steps.asMap().entries.map((stepEntry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  width: 20,
                                  height: 20,
                                  margin: const EdgeInsets.only(top: 1),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withAlpha(28),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${stepEntry.key + 1}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    stepEntry.value,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      height: 1.45,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withAlpha(140),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(
                                Icons.tips_and_updates_outlined,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.tip,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _GuideItem {
  const _GuideItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.summary,
    required this.steps,
    required this.tip,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String summary;
  final List<String> steps;
  final String tip;
}
