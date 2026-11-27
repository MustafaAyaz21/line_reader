import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_back_bridge_stub.dart'
    if (dart.library.js_interop) 'web_back_bridge_web.dart';

class _WebBackEntry {
  _WebBackEntry({
    required this.token,
    required this.hash,
    required this.onBack,
    this.route,
  });

  final Object token;
  final String hash;
  final VoidCallback onBack;
  final Route<dynamic>? route;
}

/// Web'de tarayıcı geri tuşuna basıldığında kullanıcıyı uygulama dışına
/// (ör. `getlinereader.com/app` -> `getlinereader.com`) atmak yerine
/// uygulama içi önceki rota, arama paneli veya sekmeye döndüren köprü.
///
/// Chrome/Brave'in aynı URL'li `pushState` adımlarını atlamasını (History
/// Manipulation Intervention) önlemek için hash fragment (`#/articles`,
/// `#/words`, `#/view/1` vb.) kullanır ve Flutter Web'in kendi `didPopRoute`
/// mekanizmasıyla çift `history.back()` çakışmasını hash karşılaştırmasıyla önler.
class WebBackBridge {
  WebBackBridge._();

  static final WebBackBridge shared = WebBackBridge._();

  final PlatformWebHistory _platform = PlatformWebHistory();
  final List<_WebBackEntry> _entries = <_WebBackEntry>[];
  late final NavigatorObserver navigatorObserver = _WebBackNavigatorObserver(this);

  bool _initialized = false;
  int _routeCounter = 0;

  void ensureInitialized({String initialHash = '#/articles'}) {
    if (!kIsWeb || _initialized) return;
    _initialized = true;
    _platform.initialize(_handleBrowserPopState);
    _platform.ensureBaseHash(initialHash);
  }

  /// Uygulama içi bir durum değişikliği için tarayıcı geçmişine hash adımı ekler.
  Object? pushEntry({
    required String hash,
    required VoidCallback onBack,
  }) {
    if (!kIsWeb) return null;
    ensureInitialized();
    final normalized = hash.startsWith('#') ? hash : '#$hash';
    final token = Object();
    _entries.add(
      _WebBackEntry(
        token: token,
        hash: normalized,
        onBack: onBack,
      ),
    );
    _platform.pushHash(normalized);
    return token;
  }

  /// Uygulama içi bir durum (ör. arama paneli kapatma `X` butonu) tarayıcı
  /// geri tuşu dışında kapatıldığında ilgili geçmiş adımını temizler.
  void popEntrySilently(Object? token) {
    if (!kIsWeb || token == null) return;
    final idx = _entries.lastIndexWhere((e) => identical(e.token, token));
    if (idx == -1) return;
    final entry = _entries.removeAt(idx);
    if (_platform.currentHash == entry.hash) {
      _platform.back();
    }
  }

  void _onRoutePushed(Route<dynamic> route) {
    if (!kIsWeb) return;
    if (route.isFirst || route is! PageRoute<dynamic>) return;
    ensureInitialized();
    _routeCounter++;
    final routeHash = '#/view/$_routeCounter';
    final entry = _WebBackEntry(
      token: route,
      hash: routeHash,
      route: route,
      onBack: () {
        if (route.isCurrent) {
          route.navigator?.maybePop();
        } else if (route.navigator != null && route.isActive) {
          route.navigator!.removeRoute(route);
        }
      },
    );
    _entries.add(entry);
    _platform.pushHash(routeHash);
  }

  void _onRoutePopped(Route<dynamic> route) {
    if (!kIsWeb || route is! PageRoute<dynamic>) return;
    final idx = _entries.lastIndexWhere((e) => identical(e.route, route));
    if (idx == -1) return;
    final entry = _entries.removeAt(idx);
    // Yalnızca uygulama içi geri butonundan (AppBar vb.) pop edildiyse,
    // yani tarayıcı henüz bu hash'ten geri gitmediyse history.back() çağır.
    if (_platform.currentHash == entry.hash) {
      _platform.back();
    }
  }

  void _handleBrowserPopState() {
    if (_entries.isEmpty) return;
    final currentHash = _platform.currentHash;
    final top = _entries.last;
    // Flutter'ın kendi didPopRoute'u üstteki rotayı zaten pop ettiyse ve
    // listeden çıkardıysa, currentHash artık alttaki kaydın hash'ine eşittir.
    if (top.hash == currentHash) {
      return;
    }
    _entries.removeLast();
    top.onBack();
  }
}

class _WebBackNavigatorObserver extends NavigatorObserver {
  _WebBackNavigatorObserver(this._bridge);

  final WebBackBridge _bridge;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) {
      _bridge._onRoutePushed(route);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _bridge._onRoutePopped(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _bridge._onRoutePopped(route);
  }
}
