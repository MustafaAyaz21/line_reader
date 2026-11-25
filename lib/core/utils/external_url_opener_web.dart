import 'package:web/web.dart' as web;

void openExternalUrlInNewTab(String url) {
  web.window.open(url, '_blank');
}
