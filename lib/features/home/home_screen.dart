import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/settings/api_key_controller.dart';
import '../../core/settings/settings_repository.dart';
import '../../core/tts/tts_service.dart';
import '../articles/controllers/articles_controller.dart';
import '../articles/data/articles_cache_repository.dart';
import '../articles/services/articles_sync_service.dart';
import '../browser/browser_screen.dart';
import '../translation/data/translation_cache_repository.dart';
import '../translation/models/word_meaning.dart';
import '../translation/services/cached_translation_service.dart';
import '../update/controllers/app_update_controller.dart';
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
  CachedTranslationService? _translationService;
  TtsService? _ttsService;
  AppUpdateController? _updateController;
  ArticlesController? _articlesController;
  BrowserBackController? _browserBackController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureInitialized();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdateSilently(force: true);
      _refreshArticlesSilently(force: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForAppUpdateSilently();
      _refreshArticlesSilently();
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

    _translationService ??= CachedTranslationService(
      cacheRepository: TranslationCacheRepository(AppDatabase.instance),
      geminiApiKeyProvider: () => _apiKeyController?.apiKey,
      shouldAttemptGeminiProvider: () =>
          _apiKeyController?.shouldAttemptGemini ?? false,
      onGeminiVerified: () => _apiKeyController?.markVerified(),
      onGeminiUnauthorized: (message) =>
          _apiKeyController?.markInvalid(message),
    );

    _ttsService ??= TtsService(
      geminiApiKeyProvider: () => _apiKeyController?.apiKey,
      shouldUseGeminiProvider: () =>
          _apiKeyController?.shouldAttemptGemini ?? false,
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
    _wordsController?.dispose();
    _apiKeyController?.dispose();
    _translationService?.dispose();
    _ttsService?.dispose();
    _updateController?.dispose();
    _articlesController?.dispose();
    super.dispose();
  }

  Future<SaveWordStatus> _handleAddWord(
    String word,
    String meaning,
    List<MeaningEntry> meanings,
    int? listId,
  ) {
    _ensureInitialized();
    return _wordsController!.addWord(
      word: word,
      meaning: meaning,
      meanings: meanings,
      listId: listId,
    );
  }

  Future<List<WordList>> _handleLoadWordLists() {
    _ensureInitialized();
    return _wordsController!.loadLists();
  }

  Future<void> _handleClearTranslationCache() async {
    _ensureInitialized();
    await _translationService!.clearCache();
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

  @override
  Widget build(BuildContext context) {
    _ensureInitialized();

    final canPopNormally =
        !(_selectedIndex == _mainMenuTabIndex && _isBrowserOpen);

    return PopScope(
      canPop: canPopNormally,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex == _mainMenuTabIndex && _isBrowserOpen) {
          _handleBrowserSystemBack();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _activeStackIndex,
          children: <Widget>[
            MainMenuScreen(
              key: const ValueKey<String>('main_menu_screen'),
              onOpenBrowser: _openBrowser,
              apiKeyController: _apiKeyController!,
              updateController: _updateController!,
              articlesController: _articlesController!,
              onClearCache: _handleClearTranslationCache,
            ),
            if ((_hasOpenedBrowser ?? false) || _isBrowserOpen)
              BrowserScreen(
                key: const ValueKey<String>('browser_screen'),
                onAddWord: _handleAddWord,
                loadWordLists: _handleLoadWordLists,
                translationService: _translationService!,
                ttsService: _ttsService,
                onReturnToMenu: _returnToMainMenu,
                backController: _browserBackController,
              )
            else
              const SizedBox.shrink(),
            WordsScreen(
              key: const ValueKey<String>('words_screen'),
              controller: _wordsController!,
              apiKeyController: _apiKeyController!,
              updateController: _updateController!,
              ttsService: _ttsService,
              onClearCache: _handleClearTranslationCache,
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Ana Menü',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined),
              selectedIcon: Icon(Icons.bookmarks),
              label: 'Kelimelerim',
            ),
          ],
        ),
      ),
    );
  }
}
