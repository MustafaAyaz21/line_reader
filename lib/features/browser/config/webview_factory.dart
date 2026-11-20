import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Android ve iOS için kaydırma akıcılığı ve düşük CPU/GPU yükü odaklı
/// platforma özel WebView oluşturucu.
abstract final class WebViewFactory {
  static WebViewController createController({
    required Color backgroundColor,
    required String channelName,
    required void Function(JavaScriptMessage) onMessageReceived,
    required NavigationDelegate navigationDelegate,
  }) {
    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is WebKitWebViewPlatform
            ? WebKitWebViewControllerCreationParams(
                allowsInlineMediaPlayback: true,
                mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{
                  PlaybackMediaTypes.audio,
                  PlaybackMediaTypes.video,
                },
              )
            : const PlatformWebViewControllerCreationParams();

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(backgroundColor)
      ..enableZoom(true)
      ..addJavaScriptChannel(
        channelName,
        onMessageReceived: onMessageReceived,
      )
      ..setNavigationDelegate(navigationDelegate);

    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      // Otomatik başlayan reklam/video oynatmalarının sayfa yükünü ve
      // kaydırma akıcılığını bozmasını engelle.
      platformController.setMediaPlaybackRequiresUserGesture(true);
    } else if (platformController is WebKitWebViewController) {
      // iOS'ta Safari/Chrome benzeri doğal kaydırarak geri-ileri geçişi aç.
      platformController.setAllowsBackForwardNavigationGestures(true);
    }

    return controller;
  }

  static Widget createWidget(WebViewController controller) {
    PlatformWebViewWidgetCreationParams params =
        PlatformWebViewWidgetCreationParams(
      controller: controller.platform,
    );

    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      // Texture Layer Hybrid Composition (TLHC) kullanımıyla Android'de
      // kaydırma sırasında kare düşmesini en aza indir.
      params = AndroidWebViewWidgetCreationParams
          .fromPlatformWebViewWidgetCreationParams(
        params,
        displayWithHybridComposition: false,
      );
    }

    // WebView yüzeyini üstteki Flutter UI yeniden çizimlerinden izole et.
    return RepaintBoundary(
      child: WebViewWidget.fromPlatformCreationParams(params: params),
    );
  }
}
