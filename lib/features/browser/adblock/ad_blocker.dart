/// Tarayıcı için ağ ve DOM tabanlı hafif reklam/izleyici engelleyici.
/// Kapalıyken hiçbir engelleme veya gizleme uygulanmaz.
abstract final class AdBlocker {
  static const List<String> blockedDomains = <String>[
    'doubleclick.net',
    'googlesyndication.com',
    'pagead2.googlesyndication.com',
    'googleadservices.com',
    'adservice.google.',
    'taboola.com',
    'outbrain.com',
    'criteo.com',
    'criteo.net',
    'pubmatic.com',
    'rubiconproject.com',
    'openx.net',
    'amazon-adsystem.com',
    'scorecardresearch.com',
    'zedo.com',
    'revcontent.com',
    'adnxs.com',
    'adsrvr.org',
    'advertising.com',
    'casalemedia.com',
    'mgid.com',
    'mediavine.com',
    'adthrive.com',
    'popads.net',
    'propellerads.com',
    'moatads.com',
    'quantserve.com',
    'adsystem.com',
    'ads.yahoo.com',
    '2mdn.net',
  ];

  static const List<String> blockedPathTokens = <String>[
    '/pagead/',
    '/adserver/',
    '/doubleclick/',
    '/googlesyndication/',
    '/banner_ads/',
    '/adslot',
    '/popunder',
    'adsbygoogle.js',
    '/ads.js',
  ];

  /// Verilen URL bilinen bir reklam/izleyici alan adı veya yoluyla eşleşiyorsa `true` döner.
  static bool shouldBlockUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return false;

    final host = uri.host.toLowerCase();
    final pathAndQuery = '${uri.path}?${uri.query}'.toLowerCase();

    for (final domain in blockedDomains) {
      if (domain.endsWith('.')) {
        if (host.startsWith(domain) || host.contains('.$domain')) {
          return true;
        }
      } else if (host == domain || host.endsWith('.$domain')) {
        return true;
      }
    }

    for (final token in blockedPathTokens) {
      if (pathAndQuery.contains(token)) {
        return true;
      }
    }

    return false;
  }

  static String setEnabledScript(bool enabled) {
    return 'window.__lineReaderSetAdBlock && window.__lineReaderSetAdBlock(${enabled ? 'true' : 'false'});';
  }

  static String buildInjectionScript({required bool enabled}) {
    return _baseScript.replaceFirst(
      '__INITIAL_ADBLOCK__',
      enabled ? 'true' : 'false',
    );
  }

  static const String _baseScript = r'''
(function() {
  var STYLE_ID = '__lineReaderAdBlockStyle';
  var HIDDEN_ATTR = 'data-linereader-ad-hidden';

  var BLOCKED_HOSTS = [
    'doubleclick.net',
    'googlesyndication.com',
    'pagead2.googlesyndication.com',
    'googleadservices.com',
    'adservice.google.',
    'taboola.com',
    'outbrain.com',
    'criteo.com',
    'criteo.net',
    'pubmatic.com',
    'rubiconproject.com',
    'openx.net',
    'amazon-adsystem.com',
    'scorecardresearch.com',
    'zedo.com',
    'revcontent.com',
    'adnxs.com',
    'adsrvr.org',
    'advertising.com',
    'casalemedia.com',
    'mgid.com',
    'mediavine.com',
    'adthrive.com',
    'popads.net',
    'propellerads.com',
    'moatads.com',
    'quantserve.com',
    'adsystem.com',
    '2mdn.net'
  ];

  var BLOCKED_PATHS = [
    '/pagead/',
    '/adserver/',
    '/doubleclick/',
    '/googlesyndication/',
    '/banner_ads/',
    '/adslot',
    '/popunder',
    'adsbygoogle.js',
    '/ads.js'
  ];

  function isAdUrl(rawUrl) {
    if (!rawUrl || typeof rawUrl !== 'string') return false;
    var lower = rawUrl.toLowerCase();
    for (var i = 0; i < BLOCKED_HOSTS.length; i++) {
      if (lower.indexOf(BLOCKED_HOSTS[i]) !== -1) return true;
    }
    for (var j = 0; j < BLOCKED_PATHS.length; j++) {
      if (lower.indexOf(BLOCKED_PATHS[j]) !== -1) return true;
    }
    return false;
  }

  var AD_CSS =
    'ins.adsbygoogle,' +
    '.adsbygoogle,' +
    '[data-ad-slot],' +
    '[data-google-query-id],' +
    'iframe[src*="doubleclick.net"],' +
    'iframe[src*="googlesyndication.com"],' +
    'iframe[src*="googleadservices.com"],' +
    'iframe[src*="taboola.com"],' +
    'iframe[src*="outbrain.com"],' +
    'iframe[src*="criteo."],' +
    'iframe[src*="amazon-adsystem.com"],' +
    'iframe[src*="pubmatic.com"],' +
    'iframe[src*="rubiconproject.com"],' +
    'iframe[src*="openx.net"],' +
    'iframe[src*="revcontent.com"],' +
    'iframe[id*="google_ads"],' +
    '[id*="taboola-"],' +
    '[class*="taboola"],' +
    '[id*="outbrain"],' +
    '[class*="outbrain"],' +
    '[class*="ad-banner"],' +
    '[class*="ad-container"],' +
    '[class*="ad-wrapper"],' +
    '[class*="ad_banner"],' +
    '[class*="ad_container"],' +
    '[aria-label="advertisement" i],' +
    '[aria-label="Ads" i],' +
    '[' + HIDDEN_ATTR + '="1"] {' +
    ' display: none !important;' +
    ' visibility: hidden !important;' +
    ' height: 0 !important;' +
    ' min-height: 0 !important;' +
    ' max-height: 0 !important;' +
    ' overflow: hidden !important;' +
    ' pointer-events: none !important;' +
    '}';

  function cleanupDomAds() {
    if (!window.__lineReaderAdBlockEnabled) return;
    try {
      var iframes = document.querySelectorAll('iframe');
      for (var i = 0; i < iframes.length; i++) {
        var frame = iframes[i];
        var src = frame.getAttribute('src') || '';
        var name = (frame.getAttribute('name') || '') + ' ' + (frame.getAttribute('id') || '');
        if (isAdUrl(src) || /google_ads|aswift_|ad_frame|taboola|outbrain/i.test(name)) {
          frame.setAttribute(HIDDEN_ATTR, '1');
        }
      }
      var insNodes = document.querySelectorAll('ins.adsbygoogle, ins[data-ad-client]');
      for (var k = 0; k < insNodes.length; k++) {
        insNodes[k].setAttribute(HIDDEN_ATTR, '1');
      }
    } catch (_) {}
  }

  function restoreHiddenAds() {
    try {
      var hidden = document.querySelectorAll('[' + HIDDEN_ATTR + '="1"]');
      for (var i = 0; i < hidden.length; i++) {
        hidden[i].removeAttribute(HIDDEN_ATTR);
      }
    } catch (_) {}
  }

  function applyAdBlockState(enabled) {
    window.__lineReaderAdBlockEnabled = Boolean(enabled);
    var style = document.getElementById(STYLE_ID);
    if (window.__lineReaderAdBlockEnabled) {
      if (!style) {
        style = document.createElement('style');
        style.id = STYLE_ID;
        style.textContent = AD_CSS;
        (document.head || document.documentElement).appendChild(style);
      }
      cleanupDomAds();
    } else {
      if (style && style.parentNode) {
        style.parentNode.removeChild(style);
      }
      restoreHiddenAds();
    }
  }

  window.__lineReaderSetAdBlock = applyAdBlockState;

  if (window.__lineReaderAdBlockInstalled) {
    applyAdBlockState(__INITIAL_ADBLOCK__);
    return;
  }
  window.__lineReaderAdBlockInstalled = true;

  // Ağ katmanı: fetch ve XHR reklam/izleyici isteklerini yalnızca açıkken engelle.
  if (typeof window.fetch === 'function') {
    var originalFetch = window.fetch;
    window.fetch = function(input, init) {
      var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      if (window.__lineReaderAdBlockEnabled && isAdUrl(url)) {
        return Promise.resolve(new Response('', { status: 204, statusText: 'Blocked' }));
      }
      return originalFetch.apply(this, arguments);
    };
  }

  if (window.XMLHttpRequest && window.XMLHttpRequest.prototype) {
    var origOpen = window.XMLHttpRequest.prototype.open;
    var origSend = window.XMLHttpRequest.prototype.send;
    window.XMLHttpRequest.prototype.open = function(method, url) {
      this.__lineReaderBlocked = window.__lineReaderAdBlockEnabled && isAdUrl(String(url || ''));
      return origOpen.apply(this, arguments);
    };
    window.XMLHttpRequest.prototype.send = function() {
      if (this.__lineReaderBlocked) {
        try { this.abort(); } catch (_) {}
        return;
      }
      return origSend.apply(this, arguments);
    };
  }

  applyAdBlockState(__INITIAL_ADBLOCK__);

  // Dinamik yüklenen reklamları hafif gecikmeli tekil temizlikle yakala.
  var cleanupTimer = null;
  if (typeof MutationObserver === 'function' && document.body) {
    var observer = new MutationObserver(function() {
      if (!window.__lineReaderAdBlockEnabled || cleanupTimer !== null) return;
      cleanupTimer = setTimeout(function() {
        cleanupTimer = null;
        cleanupDomAds();
      }, 450);
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }
})();
''';
}
