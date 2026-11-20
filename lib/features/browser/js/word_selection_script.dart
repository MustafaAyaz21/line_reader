/// WebView içinde kelime seçimini gerçek Android ve iOS cihazlarda kesin
/// biçimde yakalayan JavaScript köprüsü.
///
/// - Sayfa yüklendiğinde (`onPageFinished` / `onProgress`) enjekte edilir.
/// - `document.addEventListener('selectionchange', ...)` ile seçilen metni
///   ve bağlam cümlesini anında yakalar; kullanıcı parmağını kaldırdığında
///   (`touchend`) veya kısa bir bekleme sonrası (`selectionchange` debounce)
///   `LineReaderWordSelection` JavaScriptChannel üzerinden Flutter'a gönderir.
/// - Kalem modu aktifken gönderim sonrası seçimi temizler; Kalem modu
///   kapalıyken hiçbir çeviri tetiklemez (normal Kopyala / Tümünü Seç çalışır).
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
  var WORD_CHAR_REGEX;
  try {
    WORD_CHAR_REGEX = new RegExp("[\\p{L}\\p{M}'’-]", 'u');
  } catch (_) {
    WORD_CHAR_REGEX = /[A-Za-z0-9\u00C0-\u024F\u1E00-\u1EFF'’-]/;
  }

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
        // Not: user-select: none kullanilmaz ki Android/iOS native kelime
        // secimi ve selectionchange eksiksiz calissin.
        style.textContent =
          'body, body *:not(input):not(textarea):not([contenteditable="true"]) {' +
          ' -webkit-touch-callout: none !important;' +
          '}';
        (document.head || document.documentElement).appendChild(style);
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

  var selectionDebounceTimer = null;
  var touchEndFlushTimer = null;
  var latestSelection = null;
  var isTouching = false;
  var touchStartX = 0;
  var touchStartY = 0;
  var lastSentWord = '';
  var lastSentAt = 0;

  function isEditableElement(element) {
    if (!element) return false;
    var tag = element.tagName ? element.tagName.toUpperCase() : '';
    return tag === 'INPUT' || tag === 'TEXTAREA' || element.isContentEditable;
  }

  function clearSelectionTimers() {
    if (selectionDebounceTimer !== null) {
      clearTimeout(selectionDebounceTimer);
      selectionDebounceTimer = null;
    }
    if (touchEndFlushTimer !== null) {
      clearTimeout(touchEndFlushTimer);
      touchEndFlushTimer = null;
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

  function readCurrentSelectionPayload() {
    if (isEditableElement(document.activeElement)) return null;
    var selection = window.getSelection ? window.getSelection() : null;
    if (!selection || selection.rangeCount === 0) return null;

    var rawWord = selection.toString().replace(/\s+/g, ' ').trim();
    if (!rawWord) return null;

    var range = selection.getRangeAt(0);
    var sentence = '';
    try {
      sentence = extractContextSentence(
        range.startContainer,
        range.startOffset,
        rawWord
      );
    } catch (_) {}

    return { word: rawWord, sentence: sentence };
  }

  function postWordPayload(payload) {
    if (!payload || !payload.word || !window.__lineReaderPenMode) return;
    var trimmed = payload.word.replace(/\s+/g, ' ').trim();
    if (!trimmed) return;

    var normalizedKey = trimmed.toLowerCase();
    var now = Date.now();
    if (normalizedKey === lastSentWord && now - lastSentAt < 900) {
      return;
    }

    lastSentWord = normalizedKey;
    lastSentAt = now;
    latestSelection = null;
    clearSelectionTimers();

    var cleanSentence = payload.sentence ? payload.sentence.trim() : '';
    var channel = window[CHANNEL_NAME];
    if (channel && typeof channel.postMessage === 'function') {
      channel.postMessage(JSON.stringify({
        word: trimmed,
        sentence: cleanSentence
      }));
    }

    // Gonderimden sonra WebView secimini temizleyerek tutamaclari kapat.
    if (window.getSelection) {
      setTimeout(function() {
        try { window.getSelection().removeAllRanges(); } catch (_) {}
      }, 30);
    }
  }

  function flushPendingSelection() {
    if (!window.__lineReaderPenMode) return;
    var live = readCurrentSelectionPayload();
    var payload = live || latestSelection;
    if (payload && payload.word) {
      postWordPayload(payload);
    }
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
    if (offset >= text.length) offset = text.length - 1;
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
    while (start > 0 && WORD_CHAR_REGEX.test(text[start - 1])) start--;
    while (end < text.length && WORD_CHAR_REGEX.test(text[end])) end++;

    var word = text.slice(start, end);
    if (!word) return null;

    var sentence = extractContextSentence(node, start, word);
    return { word: word, sentence: sentence };
  }

  // Ana mekanizma: selectionchange ile secili metni yakala ve kisa gecikmeyle gonder.
  document.addEventListener('selectionchange', function() {
    if (!window.__lineReaderPenMode) return;
    var current = readCurrentSelectionPayload();
    if (!current) return;

    latestSelection = current;
    if (selectionDebounceTimer !== null) {
      clearTimeout(selectionDebounceTimer);
    }
    // Kullanici parmagini kaldirmasa bile kisa gecikme (260ms) sonra gonder;
    // parmagini daha erken kaldirirsa touchend aninda gonderir.
    var delay = isTouching ? 320 : 180;
    selectionDebounceTimer = setTimeout(function() {
      selectionDebounceTimer = null;
      flushPendingSelection();
    }, delay);
  }, { passive: true });

  document.addEventListener('touchstart', function(event) {
    isTouching = true;
    if (event.touches && event.touches.length === 1) {
      touchStartX = event.touches[0].clientX;
      touchStartY = event.touches[0].clientY;
    }
  }, { passive: true });

  // Kullanici secimi bitirip parmagini kaldirdiginda (touchend) secili metni hemen gonder.
  document.addEventListener('touchend', function() {
    isTouching = false;
    if (!window.__lineReaderPenMode) return;
    if (touchEndFlushTimer !== null) {
      clearTimeout(touchEndFlushTimer);
    }
    touchEndFlushTimer = setTimeout(function() {
      touchEndFlushTimer = null;
      flushPendingSelection();
    }, 60);
  }, { passive: true });

  document.addEventListener('touchcancel', function() {
    isTouching = false;
    if (!window.__lineReaderPenMode) return;
    // Android WebView uzun basmayi devralirken touchcancel tetikleyebilir;
    // hemen ardindan olusan secimi yakalamak icin kisa kontrol yap.
    if (touchEndFlushTimer !== null) {
      clearTimeout(touchEndFlushTimer);
    }
    touchEndFlushTimer = setTimeout(function() {
      touchEndFlushTimer = null;
      flushPendingSelection();
    }, 140);
  }, { passive: true });

  // Yedek mekanizma: Masaustu / baglanti uzeri uzun basma veya user-select kisitli bloklar.
  document.addEventListener('contextmenu', function(event) {
    if (!window.__lineReaderPenMode || isEditableElement(event.target)) return;
    event.preventDefault();
    var current = readCurrentSelectionPayload();
    if (current) {
      postWordPayload(current);
      return;
    }
    var cx = typeof event.clientX === 'number' && event.clientX > 0 ? event.clientX : touchStartX;
    var cy = typeof event.clientY === 'number' && event.clientY > 0 ? event.clientY : touchStartY;
    var atPoint = extractWordPayloadAtPoint(cx, cy);
    if (atPoint) {
      postWordPayload(atPoint);
    }
  });

  // Fare ile secim yapildiginda (emulator / masaustu testi) mouseup ile hemen gonder.
  document.addEventListener('mouseup', function() {
    if (!window.__lineReaderPenMode) return;
    setTimeout(flushPendingSelection, 40);
  }, { passive: true });
})();
''';
}
