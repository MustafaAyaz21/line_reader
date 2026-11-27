import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sync/cloud_sync_service.dart';

import '../../core/config/api_config.dart';
import '../../core/database/app_database.dart';
import '../../core/localization/app_locale.dart';
import '../../core/localization/app_strings.dart';
import '../../core/navigation/app_router.dart';
import '../../core/platform/process_text_channel.dart';
import '../../core/settings/api_key_controller.dart';
import '../../core/settings/display_preferences_controller.dart';
import '../../core/settings/ipa_accent_controller.dart';
import '../../core/settings/settings_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_theme_backdrop.dart';
import '../../core/tts/tts_service.dart';
import '../ads/widgets/app_banner_ad.dart';
import '../articles/controllers/article_reading_progress_controller.dart';
import '../articles/controllers/articles_controller.dart';
import '../articles/data/articles_cache_repository.dart';
import '../articles/services/articles_sync_service.dart';
import '../auth/controllers/auth_controller.dart';
import '../auth/screens/auth_screen.dart';
import '../browser/browser_screen.dart';
import '../translation/data/translation_cache_repository.dart';
import '../translation/models/word_lexicon_info.dart';
import '../translation/models/word_meaning.dart';
import '../translation/services/browser_ai_translation_service.dart';
import '../translation/services/cached_translation_service.dart';
import '../update/controllers/app_update_controller.dart';
import '../update/screens/app_update_screen.dart';
import '../update/services/app_update_service.dart';
import '../words/controllers/words_controller.dart';
import '../words/data/word_repository.dart';
import '../words/models/saved_word.dart';
import '../words/models/word_list.dart';
import '../words/words_screen.dart';
import '../settings/screens/settings_screen.dart';
import 'widgets/main_menu_screen.dart';

/// Uygulamanın iki sekmeli ana gezinme kabuğu ("Ana Menü" ve "Kelimelerim").
/// "Ana Menü" içindeki Tarayıcı kartına tıklandığında WebView ekranına geçilir
/// ve sekme geçişlerinde tarayıcı durumu korunur.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const int _mainMenuTabIndex = 0;
  static const int _wordsTabIndex = 1;

  static const int _stackMainMenuIndex = 0;
  static const int _stackBrowserIndex = 1;
  static const int _stackWordsIndex = 2;

  int _selectedIndex = _mainMenuTabIndex;
  bool _isBrowserOpen = false;
  bool? _hasOpenedBrowser;
  late final PageController _mobilePageController;
  bool _isProgrammaticPageChange = false;
  bool _wasSwipeNavigation = false;
  DateTime? _lastBackPressedAt;

  WordsController? _wordsController;
  ApiKeyController? _apiKeyController;
  CachedTranslationService? _browserTranslationService;
  CachedTranslationService? _articleTranslationService;
  TtsService? _ttsService;
  AppUpdateController? _updateController;
  ArticlesController? _articlesController;
  AuthController? _authController;
  AppLocaleController? _fallbackLocaleController;
  BrowserBackController? _browserBackController;
  WordsSearchTriggerController? _wordsSearchTriggerController;

  @override
  void initState() {
    super.initState();
    _mobilePageController = PageController()
      ..addListener(_handleMobilePageScroll);
    if (kIsWeb) {
      AppRouteController.shared.addListener(_syncTabFromRouter);
    }
    WidgetsBinding.instance.addObserver(this);
    _ensureInitialized();
    IpaAccentController.shared.load();
    DisplayPreferencesController.shared.load();
    if (!kIsWeb) {
      AppUpdateService.cleanupDownloadedUpdateApk();
    }
    ArticleReadingProgressController.shared.load();
    if (!kIsWeb) {
      ProcessTextChannel.ensureInitialized();
      ProcessTextChannel.pendingTextNotifier
          .addListener(_handleExternalProcessTextReady);
      _authController?.addListener(_handleExternalProcessTextReady);
      _updateController?.addListener(_handleExternalProcessTextReady);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) {
        _checkForAppUpdateSilently(force: true);
      }
      _refreshArticlesSilently(force: true);
      if (_authController != null) {
        CloudSyncService.shared.configure(
          authController: _authController!,
          onSyncCompleted: () {
            if (mounted) {
              _wordsController?.reloadAll();
            }
          },
        );
      }
      if (!kIsWeb) {
        _handleExternalProcessTextReady();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      CloudSyncService.shared.setAppActive(true);
      if (!kIsWeb) {
        _checkForAppUpdateSilently();
      }
      if (_authController?.isAuthenticated == true) {
        _authController!.refreshEntitlement();
        CloudSyncService.shared.syncNow();
      }
      _refreshArticlesSilently();
      _authController?.refreshEntitlement();
      _wordsController?.reloadAll();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      CloudSyncService.shared.setAppActive(false);
    }
  }

  /// Hem normal açılışta (`initState`) hem de Hot Reload sonrası eksik alan
  /// kalmaması için bağımlılıkları güvenli biçimde ilklendirir.
  void _ensureInitialized() {
    if (_wordsController == null) {
      final controller = WordsController(
        WordRepository(AppDatabase.instance),
      );
      controller.loadLists();
      _wordsController = controller;
    }

    if (_apiKeyController == null) {
      final controller = ApiKeyController(
        SettingsRepository(AppDatabase.instance),
      );
      controller.load();
      _apiKeyController = controller;
    }

    if (_authController == null) {
      final controller = AuthController();
      controller.initialize();
      _authController = controller;
    }

    bool shouldAttemptBrowserAi() {
      // Yalnızca aktivasyon kodu veya yönetici tarafından yetkilendirilmiş
      // sınırsız hesaplar tarayıcı AI bağlamsal çevirisini kullanabilir;
      // misafir ve standart hesaplar ücretsiz sözlük + yerel önbellek kullanır.
      if (!(_authController?.isUnlimited ?? false)) {
        return false;
      }
      if (ApiConfig.browserAiTranslateEndpoint.trim().startsWith('http')) {
        return true;
      }
      if (ApiConfig.managedGeminiApiKey.trim().isNotEmpty) {
        return true;
      }
      return false;
    }

    final sharedCacheRepository =
        TranslationCacheRepository(AppDatabase.instance);

    // Yalnızca Tarayıcı (web) ekranında + yetkili (sınırsız) kullanıcı için
    // bağlamsal AI (Cloudflare Workers AI) + SQLite önbellek + ücretsiz sözlük yedekli servis.
    _browserTranslationService ??= CachedTranslationService(
      cacheRepository: sharedCacheRepository,
      geminiApiKeyProvider: null,
      shouldAttemptGeminiProvider: shouldAttemptBrowserAi,
      geminiService: BrowserAiTranslationService(
        isUserAuthenticatedProvider: () =>
            _authController?.isUnlimited ?? false,
        authTokenProvider: () =>
            _authController?.getIdToken() ?? Future<String?>.value(null),
      ),
      beforeLookupQuotaCheck: () =>
          _authController?.consumeTranslationQuota() ??
          Future<bool>.value(true),
    );

    // Makale okuma ekranı için AI çağrısı yapmayan (önbellek + ücretsiz/yerel sözlük) servis.
    _articleTranslationService ??= CachedTranslationService(
      cacheRepository: sharedCacheRepository,
      geminiApiKeyProvider: null,
      shouldAttemptGeminiProvider: () => false,
      beforeLookupQuotaCheck: () =>
          _authController?.consumeTranslationQuota() ??
          Future<bool>.value(true),
    );

    _ttsService ??= TtsService(
      geminiApiKeyProvider: () => null,
      shouldUseGeminiProvider: () => false,
    );

    _updateController ??= AppUpdateController();
    if (_articlesController == null) {
      final controller = ArticlesController(
        ArticlesSyncService(
          cacheStore: ArticlesCacheRepository(AppDatabase.instance),
        ),
      );
      controller.loadCache();
      _articlesController = controller;
    }
    _browserBackController ??= BrowserBackController();
    _wordsSearchTriggerController ??= WordsSearchTriggerController();
  }

  void _handleExternalProcessTextReady() {
    if (!mounted) return;
    if (!ProcessTextChannel.hasPendingText) return;

    _ensureInitialized();
    final auth = _authController!;
    final update = _updateController!;
    // Zorunlu güncelleme, kimlik yüklemesi veya ilk açılış onboarding ekranı
    // açıkken bekleyen metni sakla; kullanıcı içeri girdiğinde hemen çalıştır.
    if (update.requiresMandatoryUpdate ||
        auth.isLoading ||
        auth.needsOnboarding) {
      return;
    }

    final query = ProcessTextChannel.consumePendingText();
    if (query == null || query.isEmpty) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _selectedIndex = _wordsTabIndex;
      _isBrowserOpen = false;
    });
    if (_mobilePageController.hasClients) {
      _isProgrammaticPageChange = true;
      _mobilePageController.jumpToPage(_stackWordsIndex);
      _isProgrammaticPageChange = false;
    }
    _wordsController!.loadLists();
    _wordsSearchTriggerController!.triggerSearch(query);
  }

  Future<void> _checkForAppUpdateSilently({bool force = false}) async {
    if (!mounted) return;

    _ensureInitialized();
    // Açılışta ve arka plandan dönüldüğünde otomatik popup göstermez;
    // yeni sürüm varsa üst bardaki güncelleme ikonunun kırmızı göstergesini yakar.
    await _updateController!.checkSilently(force: force);
  }

  Future<void> _refreshArticlesSilently({bool force = false}) async {
    if (!mounted) return;

    _ensureInitialized();
    // Uygulama açıldığında veya ön plana dönüldüğünde uzak makale kaynağını
    // sessizce kontrol eder; ağ kapalıysa mevcut yerel önbelleği korur.
    await _articlesController!.refreshSilently(force: force);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ProcessTextChannel.pendingTextNotifier
        .removeListener(_handleExternalProcessTextReady);
    _authController?.removeListener(_handleExternalProcessTextReady);
    _updateController?.removeListener(_handleExternalProcessTextReady);
    _wordsController?.dispose();
    _apiKeyController?.dispose();
    _browserTranslationService?.dispose();
    _articleTranslationService?.dispose();
    _ttsService?.dispose();
    _updateController?.dispose();
    _articlesController?.dispose();
    _authController?.dispose();
    _fallbackLocaleController?.dispose();
    _wordsSearchTriggerController?.dispose();
    _mobilePageController
      ..removeListener(_handleMobilePageScroll)
      ..dispose();
    if (kIsWeb) {
      AppRouteController.shared.removeListener(_syncTabFromRouter);
    }
    super.dispose();
  }

  Future<SaveWordStatus> _handleAddWord(
    String word,
    String meaning,
    List<MeaningEntry> meanings,
    int? listId,
  ) {
    return _handleAddWordWithLexicon(word, meaning, meanings, listId, null);
  }

  Future<SaveWordStatus> _handleAddWordWithLexicon(
    String word,
    String meaning,
    List<MeaningEntry> meanings,
    int? listId,
    WordLexiconInfo? lexicon,
  ) {
    _ensureInitialized();
    return _wordsController!.addWord(
      word: word,
      meaning: meaning,
      meanings: meanings,
      ipaUs: lexicon?.ipaUs,
      ipaUk: lexicon?.ipaUk,
      synonyms: lexicon?.synonyms ?? const <String>[],
      antonyms: lexicon?.antonyms ?? const <String>[],
      listId: listId,
    );
  }

  Future<List<WordList>> _handleLoadWordLists() {
    _ensureInitialized();
    return _wordsController!.loadLists();
  }

  Future<({WordList? list, String? error})> _handleCreateWordList(
    String name,
    int colorValue, [
    String? icon,
  ]) {
    _ensureInitialized();
    return _wordsController!.createListWithResult(
      name: name,
      colorValue: colorValue,
      icon: icon,
    );
  }

  Future<void> _handleClearTranslationCache() async {
    _ensureInitialized();
    await _browserTranslationService!.clearCache();
  }

  void _handleMobilePageScroll() {
    if (!mounted || _isProgrammaticPageChange) return;
    if (!_mobilePageController.hasClients) return;
    final page = _mobilePageController.page;
    if (page == null) return;
    // Kullanıcı Makaleler'den Tarayıcı'ya doğru kaydırmaya başladığında
    // tarayıcıyı önceden hazırla ki kaydırma sırasında boş görünmesin.
    if (page > 0.05 && !(_hasOpenedBrowser ?? false)) {
      setState(() {
        _hasOpenedBrowser = true;
      });
    }
  }

  void _onMobilePageChanged(int index) {
    if (_isProgrammaticPageChange) return;
    _ensureInitialized();
    if (index == _stackMainMenuIndex) {
      setState(() {
        _selectedIndex = _mainMenuTabIndex;
        _isBrowserOpen = false;
      });
    } else if (index == _stackBrowserIndex) {
      setState(() {
        _hasOpenedBrowser = true;
        _selectedIndex = _mainMenuTabIndex;
        _isBrowserOpen = true;
      });
    } else if (index == _stackWordsIndex) {
      setState(() {
        _selectedIndex = _wordsTabIndex;
        _isBrowserOpen = false;
      });
      if (_wordsController != null &&
          _wordsController!.lists.isEmpty &&
          !_wordsController!.isLoading) {
        _wordsController!.loadLists();
      }
    }
  }

  void _animateToMobilePage(int targetIndex) {
    if (!_mobilePageController.hasClients) return;
    final currentPage = _mobilePageController.page?.round();
    if (currentPage == targetIndex) return;
    _isProgrammaticPageChange = true;
    _mobilePageController
        .animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
      if (mounted) {
        _isProgrammaticPageChange = false;
      }
    });
  }

  AppTabRoute _tabForStackIndex(int stackIndex) {
    return switch (stackIndex) {
      _stackBrowserIndex => AppTabRoute.browser,
      _stackWordsIndex => AppTabRoute.words,
      _ => AppTabRoute.articles,
    };
  }

  int _stackIndexForTab(AppTabRoute tab) {
    return switch (tab) {
      AppTabRoute.browser => _stackBrowserIndex,
      AppTabRoute.words => _stackWordsIndex,
      AppTabRoute.articles => _stackMainMenuIndex,
    };
  }

  void _syncTabFromRouter() {
    if (!mounted) return;
    final targetStackIndex = _stackIndexForTab(AppRouteController.shared.tab);
    if (targetStackIndex == _activeStackIndex) return;
    _switchToStackIndex(targetStackIndex, updateRouter: false);
  }

  void _switchToStackIndex(
    int targetStackIndex, {
    bool updateRouter = true,
  }) {
    _ensureInitialized();
    final previousStackIndex = _activeStackIndex;
    if (previousStackIndex == targetStackIndex) return;

    if (kIsWeb && updateRouter) {
      AppRouteController.shared.setTab(_tabForStackIndex(targetStackIndex));
    }

    setState(() {
      if (targetStackIndex == _stackBrowserIndex) {
        _hasOpenedBrowser = true;
        _selectedIndex = _mainMenuTabIndex;
        _isBrowserOpen = true;
      } else if (targetStackIndex == _stackWordsIndex) {
        _selectedIndex = _wordsTabIndex;
        _isBrowserOpen = false;
      } else {
        _selectedIndex = _mainMenuTabIndex;
        _isBrowserOpen = false;
      }
    });

    _animateToMobilePage(targetStackIndex);

    if (targetStackIndex == _stackWordsIndex &&
        _wordsController != null &&
        _wordsController!.lists.isEmpty &&
        !_wordsController!.isLoading) {
      _wordsController!.loadLists();
    }
  }

  void _openBrowser() {
    _switchToStackIndex(_stackBrowserIndex);
  }

  void _returnToMainMenu() {
    if (!_isBrowserOpen) return;
    _switchToStackIndex(_stackMainMenuIndex);
  }

  Future<void> _handleBrowserSystemBack() async {
    _ensureInitialized();
    final handledInsideBrowser =
        await _browserBackController!.handleSystemBack();
    if (!handledInsideBrowser && mounted) {
      _returnToMainMenu();
    }
  }

  void _handleMobileRootSystemBack() {
    if (_selectedIndex == _mainMenuTabIndex && _isBrowserOpen) {
      _handleBrowserSystemBack();
      return;
    }

    if (_selectedIndex == _wordsTabIndex) {
      final closedSearch =
          _wordsSearchTriggerController?.handleSystemBack() ?? false;
      if (!closedSearch) {
        _switchToStackIndex(_stackMainMenuIndex);
      }
      return;
    }

    // Makaleler (Ana Menü) ekranındayken ilk geri basışta çıkış uyarısı göster,
    // 2 saniye içinde ikinci basışta uygulamadan çık.
    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      final s = context.l10n;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              s.t(
                'Çıkmak için tekrar geri tuşuna basın',
                'Press back again to exit',
              ),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    SystemNavigator.pop();
  }

  void _onDestinationSelected(int index) {
    _ensureInitialized();

    if (index == 0) {
      // Makaleler / Ana Menü
      _switchToStackIndex(_stackMainMenuIndex);
      return;
    }

    if (index == 1) {
      // Akıllı Tarayıcı
      _openBrowser();
      return;
    }

    if (index == 2) {
      // Kelimelerim
      _switchToStackIndex(_stackWordsIndex);
      return;
    }

    if (index == 3) {
      // Ayarlar
      final localeController = _resolveLocaleController(context);
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            apiKeyController: _apiKeyController!,
            localeController: localeController,
            authController: _authController!,
            onClearCache: _handleClearTranslationCache,
          ),
        ),
      );
      return;
    }
  }

  int get _activeStackIndex {
    if (_selectedIndex == _wordsTabIndex) {
      return _stackWordsIndex;
    }
    return _isBrowserOpen ? _stackBrowserIndex : _stackMainMenuIndex;
  }

  AppLocaleController _resolveLocaleController(BuildContext context) {
    return AppLocaleScope.maybeOf(context) ??
        (_fallbackLocaleController ??= AppLocaleController()..load());
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitialized();
    final localeController = _resolveLocaleController(context);
    final authController = _authController!;
    final updateController = _updateController!;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        authController,
        updateController,
      ]),
      builder: (context, _) {
        if (!kIsWeb && updateController.requiresMandatoryUpdate) {
          return AppUpdateScreen(
            controller: updateController,
            isMandatory: true,
          );
        }

        if (authController.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (authController.needsOnboarding) {
          return AuthScreen(
            controller: authController,
            canPop: false,
            initialSignUpTab: true,
          );
        }

        final s = context.l10n;
        final visuals = AppThemeVisuals.of(context);

        final isWideScreen = MediaQuery.of(context).size.width >= 840;
        final useSwipeNavigation = !kIsWeb && !isWideScreen;

        if (useSwipeNavigation && !_wasSwipeNavigation) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _mobilePageController.hasClients) {
              final target = _activeStackIndex;
              if (_mobilePageController.page?.round() != target) {
                _isProgrammaticPageChange = true;
                _mobilePageController.jumpToPage(target);
                _isProgrammaticPageChange = false;
              }
            }
          });
        }
        _wasSwipeNavigation = useSwipeNavigation;

        final mainMenuPage = RepaintBoundary(
          child: MainMenuScreen(
            key: const ValueKey<String>('main_menu_screen'),
            onOpenBrowser: _openBrowser,
            apiKeyController: _apiKeyController!,
            localeController: localeController,
            authController: authController,
            updateController: _updateController!,
            articlesController: _articlesController!,
            translationService: _articleTranslationService!,
            ttsService: _ttsService,
            onAddWord: _handleAddWord,
            onAddWordWithLexicon: _handleAddWordWithLexicon,
            loadWordLists: _handleLoadWordLists,
            onCreateWordList: _handleCreateWordList,
            onClearCache: _handleClearTranslationCache,
          ),
        );

        final browserPage = ((_hasOpenedBrowser ?? false) || _isBrowserOpen)
            ? RepaintBoundary(
                child: BrowserScreen(
                  key: const ValueKey<String>('browser_screen'),
                  onAddWord: _handleAddWord,
                  onAddWordWithLexicon: _handleAddWordWithLexicon,
                  loadWordLists: _handleLoadWordLists,
                  onCreateWordList: _handleCreateWordList,
                  translationService: _browserTranslationService!,
                  ttsService: _ttsService,
                  authController: authController,
                  onReturnToMenu: _returnToMainMenu,
                  backController: _browserBackController,
                ),
              )
            : const SizedBox.shrink();

        final wordsPage = RepaintBoundary(
          child: WordsScreen(
            key: const ValueKey<String>('words_screen'),
            controller: _wordsController!,
            apiKeyController: _apiKeyController!,
            localeController: localeController,
            authController: authController,
            updateController: _updateController!,
            ttsService: _ttsService,
            onClearCache: _handleClearTranslationCache,
            searchTriggerController: _wordsSearchTriggerController,
          ),
        );

        final bodyContent = useSwipeNavigation
            ? PageView(
                controller: _mobilePageController,
                onPageChanged: _onMobilePageChanged,
                children: <Widget>[
                  _KeepAlivePage(child: mainMenuPage),
                  _KeepAlivePage(child: browserPage),
                  _KeepAlivePage(child: wordsPage),
                ],
              )
            : IndexedStack(
                index: _activeStackIndex,
                children: <Widget>[
                  mainMenuPage,
                  browserPage,
                  wordsPage,
                ],
              );

        return PopScope(
          canPop: kIsWeb,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || kIsWeb) return;
            _handleMobileRootSystemBack();
          },
          child: AppThemeBackdrop(
            transitionKey: _activeStackIndex,
            showForegroundOverlay:
                _selectedIndex == _mainMenuTabIndex && !_isBrowserOpen,
            child: Scaffold(
              backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
              body: isWideScreen
                  ? Row(
                      children: [
                        _DesktopSidebar(
                          selectedIndex: _selectedIndex,
                          isBrowserOpen: _isBrowserOpen,
                          onSelectMainMenu: () =>
                              _switchToStackIndex(_stackMainMenuIndex),
                          onOpenBrowser: _openBrowser,
                          onSelectWords: () {
                            _switchToStackIndex(_stackWordsIndex);
                            _wordsController?.loadLists();
                          },
                          onOpenSettings: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => SettingsScreen(
                                  apiKeyController: _apiKeyController!,
                                  localeController: localeController,
                                  authController: authController,
                                  onClearCache: _handleClearTranslationCache,
                                ),
                              ),
                            );
                          },
                          authController: authController,
                          wordsController: _wordsController,
                        ),
                        Expanded(child: bodyContent),
                      ],
                    )
                  : bodyContent,
              bottomNavigationBar: isWideScreen
                  ? null
                  : Builder(
                      builder: (context) {
                        int navIndex = 0;
                        if (_selectedIndex == _wordsTabIndex) {
                          navIndex = 2;
                        } else if (_isBrowserOpen) {
                          navIndex = 1;
                        } else {
                          navIndex = 0;
                        }

                        final int totalWords = _wordsController?.lists.fold<int>(
                              0,
                              (sum, list) => sum + list.wordCount,
                            ) ??
                            0;

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppBannerAd(
                              authController: authController,
                              placement: AppBannerPlacement.bottom,
                            ),
                            NavigationBar(
                              selectedIndex: navIndex,
                              onDestinationSelected: _onDestinationSelected,
                              destinations: <NavigationDestination>[
                                NavigationDestination(
                                  icon: const Icon(Icons.menu_book_outlined),
                                  selectedIcon: const Icon(Icons.menu_book_rounded),
                                  label: s.articlesTitle,
                                ),
                                NavigationDestination(
                                  icon: const Icon(Icons.public_outlined),
                                  selectedIcon: const Icon(Icons.public_rounded),
                                  label: s.browserTitle,
                                ),
                                NavigationDestination(
                                  icon: Badge(
                                    isLabelVisible: totalWords > 0,
                                    label: Text('$totalWords'),
                                    child: const Icon(Icons.bookmarks_outlined),
                                  ),
                                  selectedIcon: Badge(
                                    isLabelVisible: totalWords > 0,
                                    label: Text('$totalWords'),
                                    child: const Icon(Icons.bookmarks),
                                  ),
                                  label: s.myWordsTitle,
                                ),
                                NavigationDestination(
                                  icon: const Icon(Icons.settings_outlined),
                                  selectedIcon: const Icon(Icons.settings_rounded),
                                  label: s.t('Ayarlar', 'Settings'),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.selectedIndex,
    required this.isBrowserOpen,
    required this.onSelectMainMenu,
    required this.onOpenBrowser,
    required this.onSelectWords,
    required this.onOpenSettings,
    required this.authController,
    this.wordsController,
  });

  final int selectedIndex;
  final bool isBrowserOpen;
  final VoidCallback onSelectMainMenu;
  final VoidCallback onOpenBrowser;
  final VoidCallback onSelectWords;
  final VoidCallback onOpenSettings;
  final AuthController authController;
  final WordsController? wordsController;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final isArticlesActive = selectedIndex == 0 && !isBrowserOpen;
    final isBrowserActive = isBrowserOpen;
    final isWordsActive = selectedIndex == 1 && !isBrowserOpen;

    final visuals = AppThemeVisuals.of(context);
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: visuals.hasBackdrop
            ? visuals.navBarColor
            : colorScheme.surfaceContainerLowest,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(65),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand Logo & Version
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.black.withAlpha(20),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    padding: const EdgeInsets.all(5),
                    child: Image.asset(
                      'assets/app_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Line Reader',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'v0.1.43',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Navigation Items
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _SidebarItem(
                    icon: Icons.menu_book_rounded,
                    label: s.articlesTitle,
                    isSelected: isArticlesActive,
                    onTap: onSelectMainMenu,
                  ),
                  const SizedBox(height: 6),
                  _SidebarItem(
                    icon: Icons.travel_explore_rounded,
                    label: s.t('Akıllı Tarayıcı', 'Smart Browser'),
                    isSelected: isBrowserActive,
                    onTap: onOpenBrowser,
                  ),
                  const SizedBox(height: 6),
                  _SidebarItem(
                    icon: Icons.bookmarks_rounded,
                    label: s.myWordsTitle,
                    isSelected: isWordsActive,
                    onTap: onSelectWords,
                    badgeCount: wordsController?.lists.fold<int>(
                      0,
                      (sum, list) =>
                          sum + (wordsController?.wordsForList(list.id).length ?? 0),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _SidebarItem(
                    icon: Icons.settings_rounded,
                    label: s.settingsTitle,
                    isSelected: false,
                    onTap: onOpenSettings,
                  ),
                ],
              ),
            ),

            const Spacer(),

            // User Profile Card at Bottom
            ListenableBuilder(
              listenable: authController,
              builder: (context, _) {
                final isAuth = authController.isAuthenticated;
                final user = authController.user;
                final displayName = isAuth && user != null
                    ? user.effectiveName
                    : s.t('Misafir Öğrenci', 'Guest Student');
                final isUnlimited = authController.isUnlimited;

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        if (isAuth) {
                          onOpenSettings();
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute<bool>(
                              builder: (_) => AuthScreen(
                                controller: authController,
                                canPop: true,
                              ),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withAlpha(60),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: colorScheme.primaryContainer,
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'L',
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      if (isUnlimited) ...[
                                        const Icon(
                                          Icons.star_rounded,
                                          size: 13,
                                          color: Color(0xFFEAB308),
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Premium',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: const Color(0xFFEAB308),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ] else ...[
                                        Text(
                                          isAuth
                                              ? s.t('Standart', 'Standard')
                                              : s.t('Giriş Yap', 'Sign In'),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bg = isSelected ? colorScheme.primary : Colors.transparent;
    final fg = isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.primary.withAlpha(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withAlpha(70),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (badgeCount != null && badgeCount! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.onPrimary.withAlpha(40)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount.toString(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mobil `PageView` içinde sekmeler arası kaydırma yapılırken alt ekranların
/// durumunu (kaydırma konumu, WebView vb.) koruyan sarmalayıcı.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
