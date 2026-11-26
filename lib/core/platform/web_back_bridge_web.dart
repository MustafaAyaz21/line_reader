import 'dart:js_interop';

typedef PopStateCallback = void Function();

@JS('window.history.pushState')
external void _jsPushState(JSAny? data, String title, String? url);

@JS('window.history.back')
external void _jsHistoryBack();

@JS('window.location.href')
external String get _jsLocationHref;

@JS('window.addEventListener')
external void _jsAddEventListener(String type, JSFunction listener);

@JS('window.removeEventListener')
external void _jsRemoveEventListener(String type, JSFunction listener);

/// Web tarayıcısının `history.pushState`, `history.back` ve `popstate`
/// olaylarını Flutter içi gezinme yığınıyla bağlar.
class PlatformWebHistory {
  JSFunction? _listener;

  void initialize(PopStateCallback onPopState) {
    if (_listener != null) return;
    _listener = ((JSAny? _) {
      onPopState();
    }).toJS;
    _jsAddEventListener('popstate', _listener!);
  }

  void pushState() {
    _jsPushState(null, '', _jsLocationHref);
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
