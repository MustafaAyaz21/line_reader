/// WebView içinde kelime seçimini tek bir net JavaScriptChannel
/// (`LineReaderSelection`) ve garantili periyodik (`350ms`) + olay tabanlı
/// tarama ile yakalayan köprü.
///
/// - Sayfa yüklendiğinde (`onPageFinished` / `onUrlChange` / `onProgress`)
///   enjekte edilir.
/// - Her `350ms`'de bir ve `selectionchange` / `touchend` olaylarında
///   `window.getSelection().toString().trim()` okunur.
/// - Boş olmayan yeni bir metin seçildiğinde seçim tutamaçlarının yerleşmesi
///   için `300ms` bekler ve metni + bağlam cümlesini
///   `window.LineReaderSelection.postMessage(...)` ile Flutter'a gönderir.
/// - Tüm işlemler `try/catch` içindedir; sayfadaki tekil bir hata dinleyiciyi
///   veya periyodik taramayı asla durdurmaz.
abstract final class WordSelectionScript {
  static const String channelName = 'LineReaderSelection';

  static const String clearSelectionScript =
      'try { window.getSelection && window.getSelection().removeAllRanges(); } catch (_) {}';

  static String setPenModeScript(bool enabled) {
    return 'try { window.__lineReaderSetPenMode && window.__lineReaderSetPenMode(${enabled ? 'true' : 'false'}); } catch (_) {}';
  }

  static String buildInjectionScript({required bool initialPenMode}) {
    return _baseInjectionScript.replaceFirst(
      '__INITIAL_PEN_MODE__',
      initialPenMode ? 'true' : 'false',
    );
  }

  static const String _baseInjectionScript = r'''
(function() {
  try {
    var CHANNEL_NAME = 'LineReaderSelection';
    var STYLE_ID = '__lineReaderPenStyle';
    var POLL_INTERVAL_MS = 350;
    var SETTLE_DELAY_MS = 300;

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
      try {
        var existing = document.getElementById(STYLE_ID);
        if (enabled) {
          if (!existing) {
            var style = document.createElement('style');
            style.id = STYLE_ID;
            // user-select: none kullanilmaz ki Android/iOS secimi calissin.
            style.textContent =
              'body, body *:not(input):not(textarea):not([contenteditable="true"]) {' +
              ' -webkit-touch-callout: none !important;' +
              '}';
            (document.head || document.documentElement).appendChild(style);
          }
        } else if (existing && existing.parentNode) {
          existing.parentNode.removeChild(existing);
        }
      } catch (_) {}
    }

    window.__lineReaderSetPenMode = function(enabled) {
      try {
        window.__lineReaderPenMode = Boolean(enabled);
        applyPenStyle(window.__lineReaderPenMode);
      } catch (_) {}
    };

    if (window.__lineReaderSelectionInstalled) {
      window.__lineReaderSetPenMode(__INITIAL_PEN_MODE__);
      return;
    }
    window.__lineReaderSelectionInstalled = true;
    window.__lineReaderSetPenMode(__INITIAL_PEN_MODE__);

    var settleTimer = null;
    var pendingText = '';
    var lastProcessedText = '';
    var lastSentAt = 0;

    function isEditableElement(element) {
      try {
        if (!element) return false;
        var tag = element.tagName ? element.tagName.toUpperCase() : '';
        return tag === 'INPUT' || tag === 'TEXTAREA' || Boolean(element.isContentEditable);
      } catch (_) {
        return false;
      }
    }

    function findContextContainer(node) {
      try {
        var current = node && node.nodeType === 3 ? node.parentElement : node;
        while (
          current &&
          current !== document.body &&
          current !== document.documentElement
        ) {
          var tag = current.tagName ? current.tagName.toUpperCase() : '';
          if (BLOCK_TAGS[tag]) return current;
          current = current.parentElement;
        }
        return node && node.parentElement ? node.parentElement : null;
      } catch (_) {
        return null;
      }
    }

    function sliceSentence(rawText, focusIndex, focusLength) {
      try {
        if (!rawText) return '';
        var text = rawText.replace(/\s+/g, ' ').trim();
        if (!text) return '';

        var idx = focusIndex;
        if (idx < 0 || idx >= text.length) idx = 0;

        var start = idx;
        while (start > 0) {
          var prev = text[start - 1];
          if (prev === '.' || prev === '!' || prev === '?' || prev === '\n') break;
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
      } catch (_) {
        return '';
      }
    }

    function extractContextSentence(selection, word) {
      try {
        if (!selection || selection.rangeCount === 0 || !word) return '';
        var range = selection.getRangeAt(0);
        var node = range.startContainer;
        var offset = range.startOffset;
        if (!node) return '';

        var container = findContextContainer(node);
        var containerText = container && container.textContent ? container.textContent : '';
        if (!container || containerText.length > 4000) {
          var localText = node.textContent || '';
          var localNorm = localText.replace(/\s+/g, ' ').trim();
          var localIdx = localNorm.toLowerCase().indexOf(word.toLowerCase());
          return sliceSentence(localText, localIdx >= 0 ? localIdx : 0, word.length);
        }

        var focusIndex = -1;
        try {
          var doc = node.ownerDocument || document;
          var prefixRange = doc.createRange();
          prefixRange.setStart(container, 0);
          var safeOffset = node.nodeType === 3
            ? Math.min(Math.max(offset, 0), (node.textContent || '').length)
            : 0;
          prefixRange.setEnd(node, safeOffset);
          focusIndex = prefixRange.toString().replace(/\s+/g, ' ').replace(/^\s+/, '').length;
        } catch (_) {
          var normalized = containerText.replace(/\s+/g, ' ').trim();
          focusIndex = normalized.toLowerCase().indexOf(word.toLowerCase());
        }

        return sliceSentence(containerText, focusIndex, word.length);
      } catch (_) {
        return '';
      }
    }

    function getActiveSelectionObject() {
      try {
        var mainSel = window.getSelection ? window.getSelection() : null;
        if (mainSel && mainSel.toString().trim().length > 0) {
          return mainSel;
        }
        // Ayni kaynakli iframe icinde secim yapildiysa onu da yakala.
        var frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
          try {
            var frameWin = frames[i].contentWindow;
            if (!frameWin || !frameWin.getSelection) continue;
            var frameSel = frameWin.getSelection();
            if (frameSel && frameSel.toString().trim().length > 0) {
              return frameSel;
            }
          } catch (_) {}
        }
      } catch (_) {}
      return null;
    }

    function sendToFlutter(word, sentence) {
      try {
        var channel = window[CHANNEL_NAME];
        if (channel && typeof channel.postMessage === 'function') {
          channel.postMessage(JSON.stringify({
            word: word,
            sentence: sentence || ''
          }));
          return true;
        }
      } catch (_) {}
      return false;
    }

    function inspectSelection() {
      try {
        if (!window.__lineReaderPenMode) {
          pendingText = '';
          if (settleTimer !== null) {
            clearTimeout(settleTimer);
            settleTimer = null;
          }
          return;
        }

        if (isEditableElement(document.activeElement)) {
          return;
        }

        var selection = getActiveSelectionObject();
        var selectedText = selection
          ? selection.toString().replace(/\s+/g, ' ').trim()
          : '';

        // Secim kaldirildiysa son islenen metni sifirla ki ayni kelime tekrar secilebilsin.
        if (!selectedText) {
          pendingText = '';
          lastProcessedText = '';
          if (settleTimer !== null) {
            clearTimeout(settleTimer);
            settleTimer = null;
          }
          return;
        }

        if (selectedText === lastProcessedText) {
          return;
        }

        // Yeni veya guncellenmis secim: tutamaclarin yerlesmesi icin 300ms bekle.
        if (selectedText !== pendingText || settleTimer === null) {
          pendingText = selectedText;
          if (settleTimer !== null) {
            clearTimeout(settleTimer);
          }
          settleTimer = setTimeout(function() {
            settleTimer = null;
            try {
              if (!window.__lineReaderPenMode) return;
              var settledSel = getActiveSelectionObject();
              var finalText = settledSel
                ? settledSel.toString().replace(/\s+/g, ' ').trim()
                : pendingText;

              if (!finalText || finalText === lastProcessedText) return;

              var now = Date.now();
              if (finalText.toLowerCase() === lastProcessedText.toLowerCase() &&
                  now - lastSentAt < 800) {
                return;
              }

              var sentence = extractContextSentence(settledSel, finalText);
              if (sendToFlutter(finalText, sentence)) {
                lastProcessedText = finalText;
                lastSentAt = now;
                pendingText = '';
              }
            } catch (_) {}
          }, SETTLE_DELAY_MS);
        }
      } catch (_) {}
    }

    // 1) Garantili 350ms periyodik tarama
    setInterval(inspectSelection, POLL_INTERVAL_MS);

    // 2) Anlik olay destekleri (selectionchange, touchend, mouseup)
    document.addEventListener('selectionchange', inspectSelection, { passive: true });
    document.addEventListener('touchend', function() {
      setTimeout(inspectSelection, 50);
    }, { passive: true });
    document.addEventListener('mouseup', function() {
      setTimeout(inspectSelection, 50);
    }, { passive: true });
  } catch (_) {}
})();
''';
}
