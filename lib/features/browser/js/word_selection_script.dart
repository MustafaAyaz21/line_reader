/// WebView içinde iki farklı metin seçim modunu (Kalem Açık / Kalem Kapalı)
/// kaydırma akıcılığını bozmadan yöneten JavaScript köprü yapılandırması:
/// - Kalem Açık: Sistemin Copy / Select All / Share menülerini engeller,
///   kelimeye basılı tutulduğunda kelime + bağlam cümlesini çeviri paneline gönderir.
/// - Kalem Kapalı: Metin seçimini serbest bırakır (native Android ActionMode
///   yalnızca Kopyala ve Tümünü Seç aksiyonlarını gösterir), çeviri panelini açmaz.
abstract final class WordSelectionScript {
  static const String channelName = 'LineReaderWordSelection';

  static const String clearSelectionScript =
      'window.getSelection && window.getSelection().removeAllRanges();';

  static String setPenModeScript(bool enabled) {
    return 'window.__lineReaderSetPenMode && window.__lineReaderSetPenMode(${enabled ? 'true' : 'false'});';
  }

  static String buildInjectionScript({required bool initialPenMode}) {
    return _baseInjectionScript.replaceFirst(
      '__INITIAL_PEN_MODE__',
      initialPenMode ? 'true' : 'false',
    );
  }

  static const String _baseInjectionScript = r'''
(function() {
  var CHANNEL_NAME = 'LineReaderWordSelection';
  var STYLE_ID = '__lineReaderPenStyle';
  var WORD_CHAR_REGEX = /[\p{L}\p{M}'’-]/u;
  var BLOCK_TAGS = {
    P: true,
    LI: true,
    DIV: true,
    BLOCKQUOTE: true,
    H1: true,
    H2: true,
    H3: true,
    H4: true,
    H5: true,
    H6: true,
    TD: true,
    TH: true,
    FIGCAPTION: true,
    ARTICLE: true,
    SECTION: true
  };

  function applyPenStyle(enabled) {
    var existing = document.getElementById(STYLE_ID);
    if (enabled) {
      if (!existing) {
        var style = document.createElement('style');
        style.id = STYLE_ID;
        style.textContent =
          'body, body *:not(input):not(textarea):not([contenteditable="true"]) {' +
          ' -webkit-touch-callout: none !important;' +
          ' -webkit-user-select: none !important;' +
          ' user-select: none !important;' +
          '}';
        (document.head || document.documentElement).appendChild(style);
      }
      if (window.getSelection) {
        try { window.getSelection().removeAllRanges(); } catch (_) {}
      }
    } else if (existing && existing.parentNode) {
      existing.parentNode.removeChild(existing);
    }
  }

  window.__lineReaderSetPenMode = function(enabled) {
    window.__lineReaderPenMode = Boolean(enabled);
    applyPenStyle(window.__lineReaderPenMode);
  };

  if (window.__lineReaderSelectionInstalled) {
    window.__lineReaderSetPenMode(__INITIAL_PEN_MODE__);
    return;
  }
  window.__lineReaderSelectionInstalled = true;
  window.__lineReaderSetPenMode(__INITIAL_PEN_MODE__);

  var longPressTimer = null;
  var scrollIdleTimer = null;
  var isScrolling = false;
  var touchStartX = 0;
  var touchStartY = 0;
  var lastSentKey = '';
  var lastSentAt = 0;

  function runWhenIdle(callback) {
    if (typeof window.requestIdleCallback === 'function') {
      window.requestIdleCallback(callback, { timeout: 200 });
    } else {
      callback();
    }
  }

  function isEditableElement(element) {
    if (!element) return false;
    var tag = element.tagName ? element.tagName.toUpperCase() : '';
    return tag === 'INPUT' || tag === 'TEXTAREA' || element.isContentEditable;
  }

  function clearLongPressTimer() {
    if (longPressTimer !== null) {
      clearTimeout(longPressTimer);
      longPressTimer = null;
    }
  }

  function findContextContainer(node) {
    var current = node && node.nodeType === Node.TEXT_NODE
      ? node.parentElement
      : node;

    while (
      current &&
      current !== document.body &&
      current !== document.documentElement
    ) {
      var tag = current.tagName ? current.tagName.toUpperCase() : '';
      if (BLOCK_TAGS[tag]) {
        return current;
      }
      current = current.parentElement;
    }
    return node && node.parentElement ? node.parentElement : null;
  }

  function sliceSentence(rawText, focusIndex, focusLength) {
    if (!rawText) return '';
    var text = rawText.replace(/\s+/g, ' ').trim();
    if (!text) return '';

    var idx = focusIndex;
    if (idx < 0 || idx >= text.length) {
      idx = 0;
    }

    var start = idx;
    while (start > 0) {
      var prev = text[start - 1];
      if (prev === '.' || prev === '!' || prev === '?' || prev === '\n') {
        break;
      }
      start--;
    }

    var end = Math.min(text.length, idx + Math.max(focusLength, 1));
    while (end < text.length) {
      var ch = text[end];
      if (ch === '.' || ch === '!' || ch === '?' || ch === '\n') {
        end++;
        break;
      }
      end++;
    }

    var sentence = text.slice(start, end).trim();
    if (sentence.length > 280) {
      var half = 130;
      var windowStart = Math.max(0, idx - half);
      var windowEnd = Math.min(text.length, idx + focusLength + half);
      sentence = text.slice(windowStart, windowEnd).trim();
    }
    return sentence;
  }

  function extractContextSentence(node, offset, word) {
    if (!node || !word) return '';

    var container = findContextContainer(node);
    var containerText = container && container.textContent
      ? container.textContent
      : '';

    if (!container || containerText.length > 4000) {
      var localText = node.textContent || '';
      var localNorm = localText.replace(/\s+/g, ' ').trim();
      var localIdx = localNorm.toLowerCase().indexOf(word.toLowerCase());
      return sliceSentence(localText, localIdx >= 0 ? localIdx : 0, word.length);
    }

    var focusIndex = -1;
    try {
      var prefixRange = document.createRange();
      prefixRange.setStart(container, 0);
      var safeOffset = node.nodeType === Node.TEXT_NODE
        ? Math.min(Math.max(offset, 0), (node.textContent || '').length)
        : 0;
      prefixRange.setEnd(node, safeOffset);
      focusIndex = prefixRange.toString().replace(/\s+/g, ' ').trimStart().length;
    } catch (_) {
      var normalized = containerText.replace(/\s+/g, ' ').trim();
      focusIndex = normalized.toLowerCase().indexOf(word.toLowerCase());
    }

    return sliceSentence(containerText, focusIndex, word.length);
  }

  function postWordPayload(word, sentence) {
    if (!word || !window.__lineReaderPenMode) return;
    var trimmed = word.trim();
    if (!trimmed) return;

    var cleanSentence = sentence ? sentence.trim() : '';
    var key = trimmed + '|' + cleanSentence;
    var now = Date.now();
    if (key === lastSentKey && now - lastSentAt < 900) {
      return;
    }

    lastSentKey = key;
    lastSentAt = now;

    var channel = window[CHANNEL_NAME];
    if (channel && typeof channel.postMessage === 'function') {
      channel.postMessage(JSON.stringify({
        word: trimmed,
        sentence: cleanSentence
      }));
    }
  }

  function extractWordPayloadAtPoint(x, y) {
    if (isScrolling) return null;
    var node = null;
    var offset = 0;

    if (document.caretRangeFromPoint) {
      var range = document.caretRangeFromPoint(x, y);
      if (range) {
        node = range.startContainer;
        offset = range.startOffset;
      }
    } else if (document.caretPositionFromPoint) {
      var position = document.caretPositionFromPoint(x, y);
      if (position) {
        node = position.offsetNode;
        offset = position.offset;
      }
    }

    if (!node || node.nodeType !== Node.TEXT_NODE || !node.textContent) {
      return null;
    }

    var text = node.textContent;
    if (offset >= text.length) {
      offset = text.length - 1;
    }
    if (offset < 0) return null;

    if (!WORD_CHAR_REGEX.test(text[offset])) {
      if (offset > 0 && WORD_CHAR_REGEX.test(text[offset - 1])) {
        offset -= 1;
      } else {
        return null;
      }
    }

    var start = offset;
    var end = offset + 1;

    while (start > 0 && WORD_CHAR_REGEX.test(text[start - 1])) {
      start--;
    }
    while (end < text.length && WORD_CHAR_REGEX.test(text[end])) {
      end++;
    }

    var word = text.slice(start, end);
    if (!word) return null;

    var sentence = extractContextSentence(node, start, word);
    return { word: word, sentence: sentence };
  }

  // Aktif kaydırma sırasında hiçbir DOM okuma/seçim sorgusu çalıştırma.
  window.addEventListener('scroll', function() {
    isScrolling = true;
    clearLongPressTimer();

    if (scrollIdleTimer !== null) {
      clearTimeout(scrollIdleTimer);
    }
    scrollIdleTimer = setTimeout(function() {
      isScrolling = false;
      scrollIdleTimer = null;
    }, 180);
  }, { passive: true, capture: true });

  // Kalem modu aktifken uzun basmada tarayıcı bağlam menüsünü engelle.
  document.addEventListener('contextmenu', function(event) {
    if (window.__lineReaderPenMode && !isEditableElement(event.target)) {
      event.preventDefault();
    }
  });

  document.addEventListener('touchstart', function(event) {
    clearLongPressTimer();
    if (!window.__lineReaderPenMode) return;
    if (isScrolling || !event.touches || event.touches.length !== 1) return;
    if (isEditableElement(event.target)) return;

    var touch = event.touches[0];
    touchStartX = touch.clientX;
    touchStartY = touch.clientY;

    longPressTimer = setTimeout(function() {
      longPressTimer = null;
      if (isScrolling || !window.__lineReaderPenMode) return;
      runWhenIdle(function() {
        var pointPayload = extractWordPayloadAtPoint(touchStartX, touchStartY);
        if (pointPayload) {
          postWordPayload(pointPayload.word, pointPayload.sentence);
        }
      });
    }, 420);
  }, { passive: true });

  document.addEventListener('touchmove', function(event) {
    if (longPressTimer === null || !event.touches || event.touches.length !== 1) {
      return;
    }
    var touch = event.touches[0];
    var dx = Math.abs(touch.clientX - touchStartX);
    var dy = Math.abs(touch.clientY - touchStartY);
    if (dx > 10 || dy > 10) {
      clearLongPressTimer();
    }
  }, { passive: true });

  document.addEventListener('touchend', clearLongPressTimer, { passive: true });
  document.addEventListener('touchcancel', clearLongPressTimer, { passive: true });
})();
''';
}
