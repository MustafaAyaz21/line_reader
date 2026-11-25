import 'external_url_opener_stub.dart'
    if (dart.library.js_interop) 'external_url_opener_web.dart' as impl;

/// Web tarayıcısında harici bir bağlantıyı yeni sekmede açar (mobilde no-op).
void openExternalUrlInNewTab(String url) => impl.openExternalUrlInNewTab(url);
