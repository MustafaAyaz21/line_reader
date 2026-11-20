import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/database/app_database.dart';
import '../../core/tts/tts_service.dart';
import '../../core/utils/url_helper.dart';
import '../translation/data/translation_cache_repository.dart';
import '../translation/models/word_meaning.dart';
import '../translation/services/cached_translation_service.dart';
import '../translation/services/word_translation_service.dart';
import '../words/data/word_repository.dart';
import '../words/models/saved_word.dart';
import '../words/models/word_list.dart';
import 'adblock/ad_blocker.dart';
import 'config/webview_factory.dart';
import 'controllers/favorite_sites_controller.dart';
import 'data/favorite_sites_repository.dart';
import 'js/word_selection_script.dart';
import 'models/favorite_site.dart';
import 'models/web_search_result.dart';
import 'models/word_selection_payload.dart';
import 'platform/selection_mode_channel.dart';
import 'services/web_search_service.dart';
import 'widgets/browser_address_bar.dart';
import 'widgets/browser_favorites_bar.dart';
import 'widgets/browser_search_results_view.dart';
import 'widgets/browser_start_view.dart';
import 'widgets/favorite_sites_sheet.dart';
import 'widgets/word_preview_sheet.dart';

typedef AddWordCallback = Future<SaveWordStatus> Function(
  String word,
  String meaning,
  List<MeaningEntry> meanings,
  int? listId,
);

enum _BrowserViewMode {
  home,
  searchResults,
  web,
}

/// Sistem geri tuşu / yandan kaydırma hareketini önce tarayıcı geçmişine
/// yönlendirmek için kullanılan hafif köprü.
class BrowserBackController {
  Future<bool> Function()? _handler;

  void attach(Future<bool> Function()? handler) {
    _handler = handler;
  }

  /// Tarayıcı içinde geri gidilecek bir sayfa/görünüm varsa `true` döner;
  /// tarayıcı geçmişi bittiyse `false` döner (Ana Menü'ye dönülebilir).
  Future<bool> handleSystemBack() async {
    final handler = _handler;
    if (handler == null) return false;
    return handler();
  }
}

/// Line Apps tasarım diline uygun, ilk açılışta harici bir sayfa (google.com vb.)
/// yüklemeyen, kendi arama kutusu ve sade sonuç listesiyle arka plan araması
/// yapan, reklam engelleyici ve Kalem modu destekli tarayıcı ekranı.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    this.onAddWord,
    this.loadWordLists,
    this.translationService,
    this.ttsService,
    this.onReturnToMenu,
    this.backController,
  });

  final AddWordCallback? onAddWord;
  final Future<List<WordList>> Function()? loadWordLists;
  final WordTranslationService? translationService;
  final TtsService? ttsService;
  final VoidCallback? onReturnToMenu;
  final BrowserBackController? backController;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _webViewController;
  late final Widget _webViewWidget;
  late final WordTranslationService _translationService;
  late final bool _ownsTranslationService;

  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();

  // Granüler ValueNotifier kullanımı sayesinde sayfa yüklenirken, ilerleme
  // güncellenirken veya mod değişirken WebViewWidget yeniden build edilmez.
  final ValueNotifier<int> _loadingProgress = ValueNotifier<int>(0);
  final ValueNotifier<bool> _canGoBack = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _canGoForward = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isPenMode = ValueNotifier<bool>(true);
  final ValueNotifier<String> _currentUrl = ValueNotifier<String>('');

  ValueNotifier<bool>? _isAdBlockerEnabled;
  ValueNotifier<_BrowserViewMode>? _viewMode;
  FavoriteSitesController? _favoriteSitesController;
  WebSearchService? _searchService;
  Listenable? _toolbarListenable;

  bool _isWordSheetOpen = false;
  bool _isBackgroundColorSynced = false;
  bool _hasEarlyInjectedCurrentPage = false;
  bool _hasLoadedAnyWebPage = false;
  bool _openedWebFromSearch = false;
  String _currentPageTitle = '';
  String? _lastTriggeredWord;
  DateTime? _lastTriggeredAt;

  // Uygulama içi arama sonuçları durumu
  String _lastSearchQuery = '';
  bool _isSearching = false;
  String? _searchError;
  List<WebSearchResult> _searchResults = const <WebSearchResult>[];
  int _searchGeneration = 0;

  bool get _isLoading {
    final progress = _loadingProgress.value;
    return progress > 0 && progress < 100;
  }

  ValueNotifier<bool> _resolveAdBlockerNotifier() {
    return _isAdBlockerEnabled ??= ValueNotifier<bool>(true);
  }

  ValueNotifier<_BrowserViewMode> _resolveViewMode() {
    return _viewMode ??= ValueNotifier<_BrowserViewMode>(_BrowserViewMode.home);
  }

  WebSearchService _resolveSearchService() {
    return _searchService ??= WebSearchService();
  }

  FavoriteSitesController _resolveFavoriteSitesController() {
    final existing = _favoriteSitesController;
    if (existing != null) return existing;

    final created = FavoriteSitesController(
      FavoriteSitesRepository(AppDatabase.instance),
    );
    created.load();
    _favoriteSitesController = created;
    return created;
  }

  Listenable _resolveToolbarListenable() {
    final existing = _toolbarListenable;
    if (existing != null) return existing;

    final merged = Listenable.merge(<Listenable>[
      _loadingProgress,
      _canGoBack,
      _canGoForward,
      _isPenMode,
      _resolveAdBlockerNotifier(),
      _currentUrl,
      _resolveViewMode(),
      _resolveFavoriteSitesController(),
    ]);
    _toolbarListenable = merged;
    return merged;
  }

  bool get _effectiveCanGoBack {
    final mode = _resolveViewMode().value;
    if (mode == _BrowserViewMode.home) return false;
    if (mode == _BrowserViewMode.searchResults) return true;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _ownsTranslationService = widget.translationService == null;
    _translationService = widget.translationService ??
        CachedTranslationService(
          cacheRepository: TranslationCacheRepository(AppDatabase.instance),
        );

    _resolveAdBlockerNotifier();
    _resolveViewMode();
    _resolveSearchService();
    _resolveFavoriteSitesController();
    _resolveToolbarListenable();
    SelectionModeChannel.setPenMode(_isPenMode.value);

    // Otomatik olarak google.com veya herhangi bir dış sayfa yüklenmez;
    // WebView yalnızca kullanıcı bir URL, favori site veya arama sonucu seçince yüklenir.
    _webViewController = WebViewFactory.createController(
      backgroundColor: Colors.white,
      channelName: WordSelectionScript.channelName,
      onMessageReceived: _handleWordSelectionMessage,
      navigationDelegate: NavigationDelegate(
        onNavigationRequest: _handleNavigationRequest,
        onPageStarted: _handlePageStarted,
        onProgress: _handleProgress,
        onPageFinished: _handlePageFinished,
        onUrlChange: (change) {
          final nextUrl = change.url;
          if (!mounted || nextUrl == null || nextUrl.isEmpty) return;
          _syncAddressBar(nextUrl);
          _injectPageScripts();
        },
        onWebResourceError: (_) {
          if (!mounted) return;
          _loadingProgress.value = 0;
        },
      ),
    );

    _webViewWidget = WebViewFactory.createWidget(_webViewController);
    widget.backController?.attach(_handleSystemBack);
  }

  @override
  void didUpdateWidget(covariant BrowserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backController != widget.backController) {
      oldWidget.backController?.attach(null);
      widget.backController?.attach(_handleSystemBack);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isBackgroundColorSynced) {
      _isBackgroundColorSynced = true;
      _webViewController.setBackgroundColor(
        Theme.of(context).colorScheme.surface,
      );
    }
  }

  @override
  void dispose() {
    widget.backController?.attach(null);
    if (_ownsTranslationService) {
      _translationService.dispose();
    }
    _favoriteSitesController?.dispose();
    _searchService?.dispose();
    _isAdBlockerEnabled?.dispose();
    _viewMode?.dispose();
    _addressController.dispose();
    _addressFocusNode.dispose();
    _loadingProgress.dispose();
    _canGoBack.dispose();
    _canGoForward.dispose();
    _isPenMode.dispose();
    _currentUrl.dispose();
    super.dispose();
  }

  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
    if (_resolveAdBlockerNotifier().value &&
        AdBlocker.shouldBlockUrl(request.url)) {
      debugPrint('[AdBlocker] Engellendi: ${request.url}');
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _handlePageStarted(String url) {
    if (!mounted) return;
    _hasEarlyInjectedCurrentPage = false;
    _syncAddressBar(url);
    _loadingProgress.value = 10;
  }

  void _handleProgress(int progress) {
    if (!mounted) return;
    final previous = _loadingProgress.value;
    // Gereksiz mikro güncellemeleri filtreleyerek ana UI thread'ini yorma.
    if (progress == 0 || progress == 100 || (progress - previous).abs() >= 5) {
      _loadingProgress.value = progress;
    }

    // Ağır haber sitelerinde `onPageFinished` gecikse bile metin göründüğü anda
    // uzun basma ve reklam temizliği çalışsın diye erken enjeksiyon yap.
    if (progress >= 65 && !_hasEarlyInjectedCurrentPage) {
      _hasEarlyInjectedCurrentPage = true;
      _injectPageScripts();
    }
  }

  Future<void> _handlePageFinished(String url) async {
    if (!mounted) return;
    _syncAddressBar(url);
    _loadingProgress.value = 100;

    await Future.wait<void>(<Future<void>>[
      _injectPageScripts(),
      _updateNavigationState(),
      _updatePageTitle(),
    ]);
  }

  Future<void> _updatePageTitle() async {
    try {
      final title = await _webViewController.getTitle();
      if (mounted && title != null && title.trim().isNotEmpty) {
        _currentPageTitle = title.trim();
      }
    } catch (_) {}
  }

  void _syncAddressBar(String url) {
    _currentUrl.value = url;
    if (_addressFocusNode.hasFocus || _addressController.text == url) return;
    _addressController.text = url;
  }

  Future<void> _injectPageScripts() async {
    try {
      await _webViewController.runJavaScript(
        WordSelectionScript.buildInjectionScript(
          initialPenMode: _isPenMode.value,
        ),
      );
    } catch (error) {
      debugPrint('[BrowserScreen] WordSelectionScript enjeksiyon hatasi: $error');
    }

    try {
      await _webViewController.runJavaScript(
        AdBlocker.buildInjectionScript(
          enabled: _resolveAdBlockerNotifier().value,
        ),
      );
    } catch (error) {
      debugPrint('[BrowserScreen] AdBlocker enjeksiyon hatasi: $error');
    }
  }

  Future<void> _openWebUrl(Uri uri, {String? initialTitle}) async {
    _addressFocusNode.unfocus();
    _currentPageTitle = initialTitle ?? '';
    _hasEarlyInjectedCurrentPage = false;
    _hasLoadedAnyWebPage = true;
    _resolveViewMode().value = _BrowserViewMode.web;
    _syncAddressBar(uri.toString());
    _loadingProgress.value = 10;
    await _webViewController.loadRequest(uri);
  }

  Future<void> _performBackgroundSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    _addressFocusNode.unfocus();
    final int myGen = ++_searchGeneration;

    setState(() {
      _lastSearchQuery = query;
      _isSearching = true;
      _searchError = null;
      _searchResults = const <WebSearchResult>[];
    });

    _currentUrl.value = '';
    _addressController.text = query;
    _loadingProgress.value = 0;
    _resolveViewMode().value = _BrowserViewMode.searchResults;

    try {
      final results = await _resolveSearchService().search(query);
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _isSearching = false;
        _searchError =
            'Arama sonuçları getirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
    }
  }

  void _returnToBrowserStart() {
    _addressFocusNode.unfocus();
    _openedWebFromSearch = false;
    _loadingProgress.value = 0;
    _currentUrl.value = '';
    _addressController.clear();
    _resolveViewMode().value = _BrowserViewMode.home;
  }

  Future<void> _handleTogglePenMode() async {
    final nextMode = !_isPenMode.value;
    _isPenMode.value = nextMode;

    await SelectionModeChannel.setPenMode(nextMode);
    if (_resolveViewMode().value == _BrowserViewMode.web) {
      try {
        await _webViewController.runJavaScript(
          WordSelectionScript.buildInjectionScript(initialPenMode: nextMode),
        );
        await _webViewController.runJavaScript(
          WordSelectionScript.setPenModeScript(nextMode),
        );
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            nextMode
                ? 'Kalem modu açık: Kelimeye basılı tutarak hızlıca çeviri açabilirsiniz.'
                : 'Kalem modu kapalı: Metin seçiminde Kopyala ve Tümünü Seç kullanılabilir.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _handleToggleAdBlocker() async {
    final notifier = _resolveAdBlockerNotifier();
    final nextEnabled = !notifier.value;
    notifier.value = nextEnabled;

    if (_resolveViewMode().value == _BrowserViewMode.web) {
      try {
        await _webViewController.runJavaScript(
          AdBlocker.buildInjectionScript(enabled: nextEnabled),
        );
        await _webViewController.runJavaScript(
          AdBlocker.setEnabledScript(nextEnabled),
        );
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            nextEnabled
                ? 'Reklam engelleyici açıldı.'
                : 'Reklam engelleyici kapatıldı.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _handleToggleFavoriteSite() async {
    if (_resolveViewMode().value != _BrowserViewMode.web ||
        _currentUrl.value.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Favorilere eklemek için önce bir web sayfası açın.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    final url = _currentUrl.value.trim();
    await _updatePageTitle();
    final controller = _resolveFavoriteSitesController();
    final added = await controller.toggleFavorite(
      title: _currentPageTitle,
      url: url,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            added
                ? 'Site favori sitelere kaydedildi.'
                : 'Site favori sitelerden çıkarıldı.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _handleOpenFavoriteSites() {
    FavoriteSitesSheet.show(
      context,
      controller: _resolveFavoriteSitesController(),
      currentUrl: _resolveViewMode().value == _BrowserViewMode.web
          ? _currentUrl.value
          : '',
      onSelectSite: _handleSelectFavoriteSite,
      onToggleCurrentSite: _handleToggleFavoriteSite,
    );
  }

  Future<void> _handleSelectFavoriteSite(FavoriteSite site) async {
    final uri = UrlHelper.tryParseDirectUrl(site.url);
    if (uri == null) return;
    _openedWebFromSearch = false;
    await _openWebUrl(uri, initialTitle: site.displayTitle);
  }

  Future<void> _handleSelectSearchResult(WebSearchResult result) async {
    final uri = UrlHelper.tryParseDirectUrl(result.url);
    if (uri == null) return;
    _openedWebFromSearch = true;
    await _openWebUrl(uri, initialTitle: result.title);
  }

  Future<void> _handleWordSelectionMessage(JavaScriptMessage message) async {
    if (!mounted || _isWordSheetOpen || !_isPenMode.value) {
      return;
    }

    final payload = WordSelectionPayload.fromMessage(message.message);
    if (payload == null || payload.word.trim().isEmpty) return;

    // Son seçilen aynı kelimenin milisaniyeler içinde çift tetiklenmesini engelle.
    final normalizedWord = payload.word.trim().toLowerCase();
    final now = DateTime.now();
    final prevAt = _lastTriggeredAt;
    if (_lastTriggeredWord == normalizedWord &&
        prevAt != null &&
        now.difference(prevAt).inMilliseconds < 900) {
      return;
    }
    _lastTriggeredWord = normalizedWord;
    _lastTriggeredAt = now;

    _addressFocusNode.unfocus();
    _isWordSheetOpen = true;
    // Seçim yakalandıktan sonra Android'deki native ActionMode / tutamaçları temizle.
    SelectionModeChannel.finishActionMode();

    try {
      // Çeviri veya veritabanı sorgusunu beklemeden BottomSheet'i ANINDA aç;
      // seçilen kelime + yükleniyor göstergesi hemen görünsün, listeler ve 4 anlam
      // geldikçe sheet içindeki state güncellensin.
      await WordPreviewSheet.show(
        context,
        word: payload.word,
        contextSentence: payload.contextSentence,
        translationService: _translationService,
        loadWordLists: widget.loadWordLists ??
            () => WordRepository(AppDatabase.instance).getAllLists(),
        ttsService: widget.ttsService,
        onAddWord: _handleAddWord,
      );
    } finally {
      _isWordSheetOpen = false;
      try {
        await _webViewController.runJavaScript(
          WordSelectionScript.clearSelectionScript,
        );
      } catch (_) {}
    }
  }

  Future<void> _handleAddWord(
    String word,
    String meaning,
    List<MeaningEntry> meanings,
    int? listId,
    String? listName,
  ) async {
    try {
      await _webViewController.runJavaScript(
        WordSelectionScript.clearSelectionScript,
      );
    } catch (_) {}

    SaveWordStatus status;
    try {
      if (widget.onAddWord != null) {
        status = await widget.onAddWord!(word, meaning, meanings, listId);
      } else {
        final repo = WordRepository(AppDatabase.instance);
        final resolvedListId =
            listId ?? await repo.getDefaultFavoritesListId();
        status = await repo.saveWord(
          listId: resolvedListId,
          word: word,
          meaning: meaning,
          meanings: meanings,
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[BrowserScreen] Kelime ekleme hatasi: $error\n$stackTrace',
      );
      status = SaveWordStatus.error;
    }

    if (!mounted) return;

    final targetName =
        (listName != null && listName.isNotEmpty) ? listName : 'Favoriler';

    final String feedback = switch (status) {
      SaveWordStatus.saved => '"$word" "$targetName" listesine kaydedildi.',
      SaveWordStatus.alreadyExists => '"$word" zaten "$targetName" listesinde.',
      SaveWordStatus.error => 'Kelime kaydedilirken bir sorun oluştu.',
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(feedback),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _updateNavigationState() async {
    final results = await Future.wait<bool>(<Future<bool>>[
      _webViewController.canGoBack(),
      _webViewController.canGoForward(),
    ]);
    if (!mounted) return;
    _canGoBack.value = results[0];
    _canGoForward.value = results[1];
  }

  Future<void> _handleSubmit(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    // Doğrudan URL/alan adı ise WebView içinde aç; arama metni ise
    // Google sayfası göstermeden kendi arka plan arama ekranımızda listele.
    final directUri = UrlHelper.tryParseDirectUrl(trimmed);
    if (directUri != null) {
      _openedWebFromSearch = false;
      await _openWebUrl(directUri);
      return;
    }

    await _performBackgroundSearch(trimmed);
  }

  /// Sistem geri tuşu / yandan kaydırma hareketini tarayıcı geçmişinde
  /// adım adım geri alarak işler. Tarayıcıda geri gidilecek ekran kalmadıysa
  /// `false` döner (Ana Menü'ye geçilebilir).
  Future<bool> _handleSystemBack() async {
    final mode = _resolveViewMode().value;
    if (mode == _BrowserViewMode.web) {
      if (await _webViewController.canGoBack()) {
        await _webViewController.goBack();
        await _updateNavigationState();
        return true;
      }
      if (_openedWebFromSearch &&
          _lastSearchQuery.isNotEmpty &&
          _searchResults.isNotEmpty) {
        _loadingProgress.value = 0;
        _currentUrl.value = '';
        _addressController.text = _lastSearchQuery;
        _resolveViewMode().value = _BrowserViewMode.searchResults;
        return true;
      }
      _returnToBrowserStart();
      return true;
    }

    if (mode == _BrowserViewMode.searchResults) {
      _returnToBrowserStart();
      return true;
    }

    return false;
  }

  Future<void> _handleBack() async {
    await _handleSystemBack();
  }

  Future<void> _handleForward() async {
    if (_resolveViewMode().value == _BrowserViewMode.web &&
        await _webViewController.canGoForward()) {
      await _webViewController.goForward();
      await _updateNavigationState();
    }
  }

  Future<void> _handleReloadOrStop() async {
    final mode = _resolveViewMode().value;
    if (mode == _BrowserViewMode.searchResults) {
      if (_lastSearchQuery.isNotEmpty) {
        await _performBackgroundSearch(_lastSearchQuery);
      }
      return;
    }

    if (mode != _BrowserViewMode.web) return;

    if (_isLoading) {
      await _webViewController.runJavaScript('window.stop();');
      if (!mounted) return;
      _loadingProgress.value = 0;
      return;
    }
    await _webViewController.reload();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final favoritesController = _resolveFavoriteSitesController();
    final toolbarListenable = _resolveToolbarListenable();
    final viewModeNotifier = _resolveViewMode();
    final adBlockerNotifier = _resolveAdBlockerNotifier();

    return SafeArea(
      child: Column(
        children: [
          ListenableBuilder(
            listenable: toolbarListenable,
            builder: (context, _) {
              final isWebMode = viewModeNotifier.value == _BrowserViewMode.web;
              return BrowserAddressBar(
                controller: _addressController,
                focusNode: _addressFocusNode,
                isLoading: isWebMode ? _isLoading : _isSearching,
                canGoBack: _effectiveCanGoBack,
                canGoForward: isWebMode && _canGoForward.value,
                isPenMode: _isPenMode.value,
                isAdBlockerEnabled: adBlockerNotifier.value,
                isCurrentSiteFavorite: isWebMode &&
                    favoritesController.isFavorite(_currentUrl.value),
                onSubmitted: _handleSubmit,
                onBack: _handleBack,
                onForward: _handleForward,
                onReloadOrStop: _handleReloadOrStop,
                onTogglePenMode: _handleTogglePenMode,
                onToggleAdBlocker: _handleToggleAdBlocker,
                onToggleFavoriteSite: _handleToggleFavoriteSite,
                onOpenFavoriteSites: _handleOpenFavoriteSites,
                onReturnToMenu: widget.onReturnToMenu,
              );
            },
          ),
          // Başlangıç ekranında favoriler zaten üstte kartlar halinde yer aldığı
          // için bu ince şerit yalnızca web/arama sonuçları görünümünde gösterilir.
          ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[
              favoritesController,
              viewModeNotifier,
            ]),
            builder: (context, _) {
              if (viewModeNotifier.value == _BrowserViewMode.home) {
                return const SizedBox.shrink();
              }
              return BrowserFavoritesBar(
                sites: favoritesController.sites,
                onSelectSite: _handleSelectFavoriteSite,
                onOpenAll: _handleOpenFavoriteSites,
              );
            },
          ),
          ValueListenableBuilder<int>(
            valueListenable: _loadingProgress,
            builder: (context, progress, _) {
              if (progress > 0 && progress < 100) {
                return LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 2.5,
                  backgroundColor: Colors.transparent,
                );
              }
              return Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outlineVariant,
              );
            },
          ),
          Expanded(
            child: ValueListenableBuilder<_BrowserViewMode>(
              valueListenable: viewModeNotifier,
              builder: (context, mode, _) {
                final int stackIndex = switch (mode) {
                  _BrowserViewMode.home => 0,
                  _BrowserViewMode.searchResults => 1,
                  _BrowserViewMode.web => 2,
                };

                return IndexedStack(
                  index: stackIndex,
                  children: <Widget>[
                    ListenableBuilder(
                      listenable: favoritesController,
                      builder: (context, _) {
                        return BrowserStartView(
                          favoriteSites: favoritesController.sites,
                          onSearch: _performBackgroundSearch,
                          onSelectFavorite: _handleSelectFavoriteSite,
                          onManageFavorites: _handleOpenFavoriteSites,
                        );
                      },
                    ),
                    BrowserSearchResultsView(
                      query: _lastSearchQuery,
                      isLoading: _isSearching,
                      results: _searchResults,
                      errorMessage: _searchError,
                      onSelectResult: _handleSelectSearchResult,
                      onRetry: () => _performBackgroundSearch(_lastSearchQuery),
                      onBackToStart: _returnToBrowserStart,
                    ),
                    // WebView'i başlangıç ekranında görünmez (offstage) başlatma;
                    // ilk kez bir web sayfası açıldığında görünür olarak bağla.
                    if (_hasLoadedAnyWebPage || mode == _BrowserViewMode.web)
                      _webViewWidget
                    else
                      const SizedBox.shrink(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
