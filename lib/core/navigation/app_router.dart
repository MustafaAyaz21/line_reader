import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AppTabRoute {
  articles,
  browser,
  words,
}

/// Uygulama içi sekme, kelime arama paneli ve alt sayfa derinliğini
/// tek bir URL/durum modeli altında temsil eder.
@immutable
class AppRouteState {
  const AppRouteState({
    this.tab = AppTabRoute.articles,
    this.isWordsSearchOpen = false,
    this.subRouteDepth = 0,
  });

  final AppTabRoute tab;
  final bool isWordsSearchOpen;
  final int subRouteDepth;

  RouteInformation toRouteInformation() {
    final base = switch (tab) {
      AppTabRoute.articles => '/articles',
      AppTabRoute.browser => '/browser',
      AppTabRoute.words => isWordsSearchOpen ? '/words/search' : '/words',
    };
    final path = subRouteDepth > 0 ? '$base/view/$subRouteDepth' : base;
    return RouteInformation(uri: Uri(path: path));
  }

  static AppRouteState fromRouteInformation(RouteInformation info) {
    final uri = info.uri;
    // Web'de hash stratejisi (#/words) veya path stratejisi (/words) desteği.
    final rawPath = uri.fragment.isNotEmpty ? uri.fragment : uri.path;
    final normalized = rawPath.trim().toLowerCase();

    AppTabRoute tab = AppTabRoute.articles;
    bool searchOpen = false;
    int depth = 0;

    if (normalized.contains('/browser')) {
      tab = AppTabRoute.browser;
    } else if (normalized.contains('/words')) {
      tab = AppTabRoute.words;
      if (normalized.contains('/words/search')) {
        searchOpen = true;
      }
    }

    final viewMatch = RegExp(r'/view/(\d+)').firstMatch(normalized);
    if (viewMatch != null) {
      depth = int.tryParse(viewMatch.group(1) ?? '0') ?? 0;
    }

    return AppRouteState(
      tab: tab,
      isWordsSearchOpen: searchOpen,
      subRouteDepth: depth,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppRouteState &&
        other.tab == tab &&
        other.isWordsSearchOpen == isWordsSearchOpen &&
        other.subRouteDepth == subRouteDepth;
  }

  @override
  int get hashCode => Object.hash(tab, isWordsSearchOpen, subRouteDepth);
}

class AppRouteInformationParser extends RouteInformationParser<AppRouteState> {
  const AppRouteInformationParser();

  @override
  Future<AppRouteState> parseRouteInformation(
    RouteInformation routeInformation,
  ) {
    return SynchronousFuture<AppRouteState>(
      AppRouteState.fromRouteInformation(routeInformation),
    );
  }

  @override
  RouteInformation? restoreRouteInformation(AppRouteState configuration) {
    return configuration.toRouteInformation();
  }
}

/// Sekme, arama paneli ve `Navigator.push` alt sayfalarını tek merkezden
/// yöneten durum denetleyicisi.
class AppRouteController extends ChangeNotifier {
  AppRouteController._();

  static final AppRouteController shared = AppRouteController._();

  AppTabRoute _tab = AppTabRoute.articles;
  bool _isWordsSearchOpen = false;
  int _subRouteDepth = 0;
  bool _suppressObserverUpdates = false;
  VoidCallback? _closeWordsSearchHandler;

  AppTabRoute get tab => _tab;
  bool get isWordsSearchOpen => _isWordsSearchOpen;
  int get subRouteDepth => _subRouteDepth;

  AppRouteState get currentState => AppRouteState(
        tab: _tab,
        isWordsSearchOpen: _isWordsSearchOpen,
        subRouteDepth: _subRouteDepth,
      );

  void attachCloseWordsSearchHandler(VoidCallback? handler) {
    _closeWordsSearchHandler = handler;
  }

  void setTab(AppTabRoute tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  void setWordsSearchOpen(bool open) {
    if (_isWordsSearchOpen == open) return;
    _isWordsSearchOpen = open;
    notifyListeners();
  }

  void _onSubRoutePushed() {
    if (_suppressObserverUpdates) return;
    _subRouteDepth++;
    notifyListeners();
  }

  void _onSubRoutePopped() {
    if (_suppressObserverUpdates) return;
    if (_subRouteDepth > 0) {
      _subRouteDepth--;
      notifyListeners();
    }
  }

  void _applyFromRouter({
    required AppRouteState configuration,
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    final nav = navigatorKey.currentState;
    if (nav != null && _subRouteDepth > configuration.subRouteDepth) {
      _suppressObserverUpdates = true;
      var toPop = _subRouteDepth - configuration.subRouteDepth;
      while (toPop > 0 && nav.canPop()) {
        nav.pop();
        toPop--;
      }
      _suppressObserverUpdates = false;
    }

    if (_isWordsSearchOpen && !configuration.isWordsSearchOpen) {
      _closeWordsSearchHandler?.call();
    }

    final changed = _tab != configuration.tab ||
        _isWordsSearchOpen != configuration.isWordsSearchOpen ||
        _subRouteDepth != configuration.subRouteDepth;

    _tab = configuration.tab;
    _isWordsSearchOpen = configuration.isWordsSearchOpen;
    _subRouteDepth = configuration.subRouteDepth;

    if (changed) {
      notifyListeners();
    }
  }
}

/// Flutter'ın resmi `RouterDelegate` + `PopNavigatorRouterDelegateMixin`
/// uygulaması. Hem Web'de tarayıcı geri/ileri tuşlarını tek otorite olarak
/// yönetir hem de mevcut `Navigator.push` çağrılarını destekler.
class AppRouterDelegate extends RouterDelegate<AppRouteState>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRouteState> {
  AppRouterDelegate({
    required this.controller,
    required this.homeBuilder,
  }) {
    controller.addListener(notifyListeners);
    _observer = _AppRouteNavigatorObserver(controller);
  }

  final AppRouteController controller;
  final WidgetBuilder homeBuilder;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  late final _AppRouteNavigatorObserver _observer;

  @override
  AppRouteState? get currentConfiguration =>
      kIsWeb ? controller.currentState : null;

  @override
  Future<void> setNewRoutePath(AppRouteState configuration) {
    controller._applyFromRouter(
      configuration: configuration,
      navigatorKey: navigatorKey,
    );
    return SynchronousFuture<void>(null);
  }

  @override
  void dispose() {
    controller.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: <NavigatorObserver>[_observer],
      pages: <Page<dynamic>>[
        MaterialPage<void>(
          key: const ValueKey<String>('app_home_page'),
          child: homeBuilder(context),
        ),
      ],
      onPopPage: (Route<dynamic> route, dynamic result) {
        return route.didPop(result);
      },
    );
  }
}

class _AppRouteNavigatorObserver extends NavigatorObserver {
  _AppRouteNavigatorObserver(this._controller);

  final AppRouteController _controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null && route is PageRoute<dynamic>) {
      _controller._onSubRoutePushed();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute<dynamic> && !route.isFirst) {
      _controller._onSubRoutePopped();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (route is PageRoute<dynamic> && !route.isFirst) {
      _controller._onSubRoutePopped();
    }
  }
}
