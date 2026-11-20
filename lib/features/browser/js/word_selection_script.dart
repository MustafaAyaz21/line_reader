/// WebView içinde iki farklı metin seçim modunu (Kalem Açık / Kalem Kapalı)
/// gerçek cihazlarda ve emülatörlerde kararlı biçimde yöneten JS köprüsü:
/// - Kalem Açık: `user-select: none` KULLANMADAN (Android Chromium'da
///   `caretRangeFromPoint` bozulmasın diye) basılı tutma, `contextmenu` ve
///   `selectionchange` olaylarını birlikte yakalar; native sistem menüsü
///   Android `MainActivity.onActionModeStarted` tarafından engellenir ve
///   kelime + bağlam cümlesi doğrudan çeviri BottomSheet'ine iletilir.
/// - Kalem Kapalı: Çeviri panelini tetiklemez; normal metin seçimi çalışır ve
///   Android sistem menüsünde yalnızca Kopyala + Tümünü Seç bırakılır.
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
        // Not: user-select: none Android WebView'de caretRangeFromPoint'i
        // bozduğu için kullanılmaz; yalnızca touch-callout bastırılır.
        style.textContent =
          'body, body *:not(input):not(textarea):not([contenteditable="true"]) {' +
          ' -webkit-touch-callout: none !important;' +
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
  var selectionTimer = null;
  var pendingSelection = null;
  var scrollIdleTimer = null;
  var isScrolling = false;
  var touchStartX = 0;
  var touchStartY = 0;
  var lastSentKey = '';
  var lastSentAt = 0;

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

  function clearSelectionTimer() {
    if (selectionTimer !== null) {
      clearTimeout(selectionTimer);
      selectionTimer = null;
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
      focusIndex = prefixRange.toString().replace(/\s+/g, ' ').replace(/^\s+/, '').length;
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

    if (window.getSelection) {
      try { window.getSelection().removeAllRanges(); } catch (_) {}
    }

    var channel = window[CHANNEL_NAME];
    if (channel && typeof channel.postMessage === 'function') {
      channel.postMessage(JSON.stringify({
        word: trimmed,
        sentence: cleanSentence
      }));
    }
  }

  function getSelectionPayload() {
    if (isScrolling || isEditableElement(document.activeElement)) return null;
    var selection = window.getSelection ? window.getSelection() : null;
    if (!selection || selection.rangeCount === 0) return null;

    var word = selection.toString().trim();
    if (!word) return null;

    var range = selection.getRangeAt(0);
    var sentence = extractContextSentence(
      range.startContainer,
      range.startOffset,
      word
    );
    return { word: word, sentence: sentence };
  }

  function findTextNodeInElementAtPoint(element, x, y) {
    if (!element || !element.childNodes) return null;
    var walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, null);
    var textNode;
    while ((textNode = walker.nextNode())) {
      if (!textNode.textContent || !textNode.textContent.trim()) continue;
      try {
        var r = document.createRange();
        r.selectNodeContents(textNode);
        var rects = r.getClientRects();
        for (var i = 0; i < rects.length; i++) {
          var rect = rects[i];
          if (x >= rect.left - 6 && x <= rect.right + 6 &&
              y >= rect.top - 6 && y <= rect.bottom + 6) {
            // Yaklaşık karakter konumunu yatay orandan hesapla
            var ratio = rect.width > 0 ? (x - rect.left) / rect.width : 0;
            ratio = Math.max(0, Math.min(1, ratio));
            var approxOffset = Math.floor(ratio * textNode.textContent.length);
            return { node: textNode, offset: approxOffset };
          }
        }
      } catch (_) {}
    }
    return null;
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

    if (node && node.nodeType !== Node.TEXT_NODE) {
      var found = findTextNodeInElementAtPoint(node, x, y);
      if (found) {
        node = found.node;
        offset = found.offset;
      }
    }

    if (!node || node.nodeType !== Node.TEXT_NODE) {
      var el = document.elementFromPoint ? document.elementFromPoint(x, y) : null;
      if (el && !isEditableElement(el)) {
        var fromEl = findTextNodeInElementAtPoint(el, x, y);
        if (fromEl) {
          node = fromEl.node;
          offset = fromEl.offset;
        }
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
      } else if (offset + 1 < text.length && WORD_CHAR_REGEX.test(text[offset + 1])) {
        offset += 1;
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

  function emitWordForPointOrSelection(x, y) {
    if (!window.__lineReaderPenMode || isScrolling) return;
    var selected = getSelectionPayload();
    if (selected) {
      postWordPayload(selected.word, selected.sentence);
      return;
    }
    var atPoint = extractWordPayloadAtPoint(x, y);
    if (atPoint) {
      postWordPayload(atPoint.word, atPoint.sentence);
    }
  }

  // Aktif kaydırma sırasında hiçbir DOM okuma/seçim sorgusu çalıştırma.
  window.addEventListener('scroll', function() {
    isScrolling = true;
    pendingSelection = null;
    clearLongPressTimer();
    clearSelectionTimer();

    if (scrollIdleTimer !== null) {
      clearTimeout(scrollIdleTimer);
    }
    scrollIdleTimer = setTimeout(function() {
      isScrolling = false;
      scrollIdleTimer = null;
    }, 180);
  }, { passive: true, capture: true });

  // Sinyal 1: Kalem modu aktifken uzun basmada bağlam menüsünü engelleyip kelimeyi yakala.
  document.addEventListener('contextmenu', function(event) {
    if (!window.__lineReaderPenMode || isEditableElement(event.target)) return;
    event.preventDefault();
    clearLongPressTimer();
    var cx = typeof event.clientX === 'number' && event.clientX > 0 ? event.clientX : touchStartX;
    var cy = typeof event.clientY === 'number' && event.clientY > 0 ? event.clientY : touchStartY;
    emitWordForPointOrSelection(cx, cy);
  });

  // Sinyal 2: Kalem modu aktifken Android WebView'in uzun basma ile seçtiği
  // kelimeyi senkron yakala (MainActivity mode.finish() seçimi hemen temizlese
  // bile yakalanan kelime kaybolmasın).
  document.addEventListener('selectionchange', function() {
    if (!window.__lineReaderPenMode || isScrolling) return;
    var selected = getSelectionPayload();
    if (!selected) return;

    pendingSelection = selected;
    clearSelectionTimer();
    selectionTimer = setTimeout(function() {
      selectionTimer = null;
      var payload = pendingSelection;
      pendingSelection = null;
      if (!window.__lineReaderPenMode || isScrolling || !payload) return;
      postWordPayload(payload.word, payload.sentence);
    }, 50);
  }, { passive: true });

  // Sinyal 3: Doğrudan parmakla basılı tutma (380ms, gerçek parmak titreşimine toleranslı).
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
      emitWordForPointOrSelection(touchStartX, touchStartY);
    }, 380);
  }, { passive: true });

  document.addEventListener('touchmove', function(event) {
    if (longPressTimer === null || !event.touches || event.touches.length !== 1) {
      return;
    }
    var touch = event.touches[0];
    var dx = Math.abs(touch.clientX - touchStartX);
    var dy = Math.abs(touch.clientY - touchStartY);
    if (dx > 18 || dy > 18) {
      clearLongPressTimer();
    }
  }, { passive: true });

  document.addEventListener('touchend', clearLongPressTimer, { passive: true });
  document.addEventListener('touchcancel', clearLongPressTimer, { passive: true });
})();
''';
}
