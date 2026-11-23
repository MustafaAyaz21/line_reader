import 'package:flutter/material.dart';

import '../../core/config/api_config.dart';
import '../../core/database/app_database.dart';
import '../../core/localization/app_locale.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/process_text_channel.dart';
import '../../core/settings/api_key_controller.dart';
import '../../core/settings/display_preferences_controller.dart';
import '../../core/settings/ipa_accent_controller.dart';
import '../../core/settings/settings_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_theme_backdrop.dart';
import '../../core/tts/tts_service.dart';
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
    WidgetsBinding.instance.addObserver(this);
    _ensureInitialized();
    IpaAccentController.shared.load();
    DisplayPreferencesController.shared.load();
    AppUpdateService.cleanupDownloadedUpdateApk();
    ArticleReadingProgressController.shared.load();
    ProcessTextChannel.ensureInitialized();
    ProcessTextChannel.pendingTextNotifier
        .addListener(_handleExternalProcessTextReady);
    _authController?.addListener(_handleExternalProcessTextReady);
    _updateController?.addListener(_handleExternalProcessTextReady);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdateSilently(force: true);
      _refreshArticlesSilently(force: true);
      _handleExternalProcessTextReady();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForAppUpdateSilently();
      _refreshArticlesSilently();
      _authController?.refreshEntitlement();
      _wordsController?.loadLists();
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
    int colorValue,
  ) {
    _ensureInitialized();
    return _wordsController!.createListWithResult(
      name: name,
      colorValue: colorValue,
    );
  }

  Future<void> _handleClearTranslationCache() async {
    _ensureInitialized();
    await _browserTranslationService!.clearCache();
  }

  void _openBrowser() {
    _ensureInitialized();
    setState(() {
      _hasOpenedBrowser = true;
      _selectedIndex = _mainMenuTabIndex;
      _isBrowserOpen = true;
    });
  }

  void _returnToMainMenu() {
    if (!_isBrowserOpen) return;
    setState(() {
      _isBrowserOpen = false;
    });
  }

  Future<void> _handleBrowserSystemBack() async {
    _ensureInitialized();
    final handledInsideBrowser =
        await _browserBackController!.handleSystemBack();
    if (!handledInsideBrowser && mounted) {
      _returnToMainMenu();
    }
  }

  void _onDestinationSelected(int index) {
    _ensureInitialized();

    if (index == _mainMenuTabIndex) {
      if (_selectedIndex == _mainMenuTabIndex && _isBrowserOpen) {
        // Tarayıcı açıkken "Ana Menü" sekmesine tekrar dokunulursa menüye dön.
        setState(() => _isBrowserOpen = false);
        return;
      }
      if (_selectedIndex != _mainMenuTabIndex) {
        setState(() => _selectedIndex = _mainMenuTabIndex);
      }
      return;
    }

    if (index == _wordsTabIndex) {
      if (_selectedIndex != _wordsTabIndex) {
        setState(() => _selectedIndex = _wordsTabIndex);
      }
      _wordsController!.loadLists();
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
        if (updateController.requiresMandatoryUpdate) {
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
        final canPopNormally =
            !(_selectedIndex == _mainMenuTabIndex && _isBrowserOpen);

        return PopScope(
          canPop: canPopNormally,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop &&
                _selectedIndex == _mainMenuTabIndex &&
                _isBrowserOpen) {
              _handleBrowserSystemBack();
            }
          },
          child: AppThemeBackdrop(
            child: Scaffold(
              backgroundColor: visuals.hasBackdrop ? Colors.transparent : null,
              body: IndexedStack(
              index: _activeStackIndex,
              children: <Widget>[
                MainMenuScreen(
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
                if ((_hasOpenedBrowser ?? false) || _isBrowserOpen)
                  BrowserScreen(
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
                  )
                else
                  const SizedBox.shrink(),
                WordsScreen(
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
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              destinations: <NavigationDestination>[
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: s.mainMenuTitle,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.bookmarks_outlined),
                  selectedIcon: const Icon(Icons.bookmarks),
                  label: s.myWordsTitle,
                ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }
}
