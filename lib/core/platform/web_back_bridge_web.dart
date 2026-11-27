import 'dart:js_interop';

typedef PopStateCallback = void Function();

@JS('window.history.pushState')
external void _jsPushState(JSAny? data, String title, String? url);

@JS('window.history.replaceState')
external void _jsReplaceState(JSAny? data, String title, String? url);

@JS('window.history.back')
external void _jsHistoryBack();

@JS('window.location.pathname')
external String get _jsLocationPathname;

@JS('window.location.search')
external String get _jsLocationSearch;

@JS('window.location.hash')
external String get _jsLocationHash;

@JS('window.addEventListener')
external void _jsAddEventListener(String type, JSFunction listener);

@JS('window.removeEventListener')
external void _jsRemoveEventListener(String type, JSFunction listener);

/// Web tarayıcısının hash URL tabanlı `history.pushState`, `history.back` ve
/// `popstate` olaylarını Flutter içi gezinme yığınıyla bağlar.
class PlatformWebHistory {
  JSFunction? _listener;

  void initialize(PopStateCallback onPopState) {
    if (_listener != null) return;
    _listener = ((JSAny? _) {
      onPopState();
    }).toJS;
    _jsAddEventListener('popstate', _listener!);
  }

  String get currentHash => _jsLocationHash;

  String _buildUrlWithHash(String hash) {
    final normalized = hash.startsWith('#') ? hash : '#$hash';
    return '$_jsLocationPathname$_jsLocationSearch$normalized';
  }

  void ensureBaseHash(String hash) {
    if (_jsLocationHash.isEmpty) {
      _jsReplaceState(null, '', _buildUrlWithHash(hash));
    }
  }

  void pushHash(String hash) {
    _jsPushState(null, '', _buildUrlWithHash(hash));
  }

  void back() {
    _jsHistoryBack();
  }

  void dispose() {
    final listener = _listener;
    if (listener != null) {
      _jsRemoveEventListener('popstate', listener);
      _listener = null;
    }
  }
}
