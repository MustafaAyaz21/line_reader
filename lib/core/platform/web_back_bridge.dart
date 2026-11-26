import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_back_bridge_stub.dart'
    if (dart.library.js_interop) 'web_back_bridge_web.dart';

class _WebBackEntry {
  _WebBackEntry({
    required this.token,
    required this.onBack,
    this.route,
  });

  final Object token;
  final VoidCallback onBack;
  final Route<dynamic>? route;
  bool poppedByBrowser = false;
}

/// Web'de tarayıcı geri tuşuna basıldığında kullanıcıyı uygulama dışına
/// (ör. `getlinereader.com/app` -> `getlinereader.com`) atmak yerine
/// uygulama içi önceki rota, arama paneli veya sekmeye döndüren köprü.
class WebBackBridge {
  WebBackBridge._();

  static final WebBackBridge shared = WebBackBridge._();

  final PlatformWebHistory _platform = PlatformWebHistory();
  final List<_WebBackEntry> _entries = <_WebBackEntry>[];
  late final NavigatorObserver navigatorObserver = _WebBackNavigatorObserver(this);

  bool _initialized = false;
  int _suppressPopStateCount = 0;

  void ensureInitialized() {
    if (!kIsWeb || _initialized) return;
    _initialized = true;
    _platform.initialize(_handleBrowserPopState);
  }

  /// Uygulama içi bir durum değişikliği için tarayıcı geçmişine adım ekler.
  /// Döndürülen token, durum kullanıcı tarafından manuel kapatıldığında
  /// [popEntrySilently] ile geçmişi senkronize etmek için kullanılabilir.
  Object? pushEntry({required VoidCallback onBack}) {
    if (!kIsWeb) return null;
    ensureInitialized();
    final token = Object();
    _entries.add(_WebBackEntry(token: token, onBack: onBack));
    _platform.pushState();
    return token;
  }

  /// Uygulama içi bir durum (ör. arama paneli kapatma `X` butonu) tarayıcı
  /// geri tuşu dışında kapatıldığında ilgili geçmiş adımını temizler.
  void popEntrySilently(Object? token) {
    if (!kIsWeb || token == null) return;
    final idx = _entries.lastIndexWhere((e) => identical(e.token, token));
    if (idx == -1) return;
    _entries.removeAt(idx);
    _suppressPopStateCount++;
    _platform.back();
  }

  void _onRoutePushed(Route<dynamic> route) {
    if (!kIsWeb) return;
    // İlk root route için geçmiş kaydı eklenmez.
    if (route.isFirst) return;
    ensureInitialized();
    final entry = _WebBackEntry(
      token: route,
      route: route,
      onBack: () {
        if (route.isCurrent) {
          route.navigator?.maybePop();
        } else if (route.navigator != null) {
          route.navigator!.removeRoute(route);
        }
      },
    );
    _entries.add(entry);
    _platform.pushState();
  }

  void _onRoutePopped(Route<dynamic> route) {
    if (!kIsWeb) return;
    final idx = _entries.lastIndexWhere((e) => identical(e.route, route));
    if (idx == -1) return;
    final entry = _entries.removeAt(idx);
    if (!entry.poppedByBrowser) {
      _suppressPopStateCount++;
      _platform.back();
    }
  }

  void _handleBrowserPopState() {
    if (_suppressPopStateCount > 0) {
      _suppressPopStateCount--;
      return;
    }
    if (_entries.isEmpty) return;
    final entry = _entries.removeLast();
    entry.poppedByBrowser = true;
    entry.onBack();
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
