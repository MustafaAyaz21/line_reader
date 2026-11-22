import '../models/article_reader_models.dart';

/// Sesli okuma (TTS & Podcast AI) cümle-cümle takibi ve vurgulaması için
/// tek bir cümlenin paragraf içi konumu ve metni.
class ArticleSentenceSpan {
  const ArticleSentenceSpan({
    required this.paragraphIndex,
    required this.sentenceIndex,
    required this.startOffset,
    required this.endOffset,
    required this.text,
  });

  final int paragraphIndex;
  final int sentenceIndex;
  final int startOffset;
  final int endOffset;
  final String text;
}

/// Paragraf içinde tek bir işlenmiş parça (kelime veya boşluk/noktalama)
/// ve varsa kapsayan alt çizgi bilgisi.
class ArticleRenderSegment {
  const ArticleRenderSegment({
    required this.start,
    required this.end,
    required this.text,
    required this.isWord,
    this.underline,
  });

  final int start;
  final int end;
  final String text;
  final bool isWord;
  final ArticleUnderline? underline;

  bool get isUnderlined => underline != null;
}

/// Yerel okuma ekranı için paragraf bölme, kelime tokenizasyonu, bağlam
/// cümlesi çıkarma ve alt çizgi aralığı birleştirme yardımcıları.
abstract final class ArticleTextParser {
  static final RegExp _wordPattern = RegExp(
    r"[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*",
    unicode: true,
  );
  static final RegExp _blankLineSplit = RegExp(r'\n\s*\n+');
  static final RegExp _sentenceBoundary = RegExp(r'[.!?\n]');
  static const Set<String> _nonBreakingAbbrev = <String>{
    'mr',
    'mrs',
    'ms',
    'dr',
    'prof',
    'sr',
    'jr',
    'st',
    'vs',
    'etc',
    'e.g',
    'i.e',
    'u.s',
    'u.k',
  };

  /// Paragraf listesini sesli okuma ve canlı vurgulama için cümlelere böler.
  /// Yaygın kısaltmalar (`Dr.`, `Mr.`, `U.S.`, `3.5` vb.) cümle sonu sayılmaz.
  static List<ArticleSentenceSpan> splitParagraphSentences(
    List<String> paragraphs,
  ) {
    final result = <ArticleSentenceSpan>[];
    var globalSentenceIndex = 0;

    for (var pIdx = 0; pIdx < paragraphs.length; pIdx++) {
      final paragraph = paragraphs[pIdx];
      if (paragraph.trim().isEmpty) continue;

      var segStart = 0;
      var i = 0;
      while (i < paragraph.length) {
        final ch = paragraph[i];
        if (ch == '.' || ch == '!' || ch == '?') {
          if (ch == '.' && _isNonBreakingPeriod(paragraph, i)) {
            i++;
            continue;
          }

          var end = i + 1;
          // Birden fazla noktalama (`...`, `?!`) ve kapanış tırnaklarını dahil et.
          while (end < paragraph.length &&
              (paragraph[end] == '.' ||
                  paragraph[end] == '!' ||
                  paragraph[end] == '?' ||
                  paragraph[end] == '"' ||
                  paragraph[end] == "'" ||
                  paragraph[end] == '”' ||
                  paragraph[end] == '’' ||
                  paragraph[end] == ')')) {
            end++;
          }

          final atEndOrSpace =
              end >= paragraph.length || paragraph[end].trim().isEmpty;
          if (atEndOrSpace) {
            final slice = _trimSpan(paragraph, segStart, end);
            if (slice != null) {
              result.add(
                ArticleSentenceSpan(
                  paragraphIndex: pIdx,
                  sentenceIndex: globalSentenceIndex++,
                  startOffset: slice.start,
                  endOffset: slice.end,
                  text: slice.text,
                ),
              );
            }
            segStart = end;
            i = end;
            continue;
          }
        }
        i++;
      }

      if (segStart < paragraph.length) {
        final slice = _trimSpan(paragraph, segStart, paragraph.length);
        if (slice != null) {
          result.add(
            ArticleSentenceSpan(
              paragraphIndex: pIdx,
              sentenceIndex: globalSentenceIndex++,
              startOffset: slice.start,
              endOffset: slice.end,
              text: slice.text,
            ),
          );
        }
      }
    }

    return List<ArticleSentenceSpan>.unmodifiable(result);
  }

  static bool _isNonBreakingPeriod(String text, int dotIndex) {
    // Ondalık sayı (örn. 3.14)
    if (dotIndex > 0 &&
        dotIndex + 1 < text.length &&
        _isDigit(text.codeUnitAt(dotIndex - 1)) &&
        _isDigit(text.codeUnitAt(dotIndex + 1))) {
      return true;
    }

    // Kısaltma kontrolü (Mr., Dr., U.S., e.g. vb.)
    var tokenStart = dotIndex - 1;
    while (tokenStart >= 0 &&
        text[tokenStart].trim().isNotEmpty &&
        text[tokenStart] != '(' &&
        text[tokenStart] != '"') {
      tokenStart--;
    }
    final token = text.substring(tokenStart + 1, dotIndex).toLowerCase();
    if (_nonBreakingAbbrev.contains(token)) return true;
    // Tek harfli baş harf (J. K. Rowling gibi)
    if (token.length == 1 && RegExp(r'^[a-z]$').hasMatch(token)) {
      return true;
    }
    return false;
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

  static ({int start, int end, String text})? _trimSpan(
    String source,
    int rawStart,
    int rawEnd,
  ) {
    var s = rawStart;
    var e = rawEnd;
    while (s < e && source[s].trim().isEmpty) {
      s++;
    }
    while (e > s && source[e - 1].trim().isEmpty) {
      e--;
    }
    if (e <= s) return null;
    final text = source.substring(s, e);
    if (text.trim().isEmpty) return null;
    return (start: s, end: e, text: text);
  }

  /// Ham makale içeriğini temiz paragraf listesine böler.
  static List<String> splitParagraphs(String rawContent) {
    final normalized = rawContent.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const <String>[];

    final parts = normalized.contains('\n\n')
        ? normalized.split(_blankLineSplit)
        : normalized.split('\n');

    return parts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  /// Paragrafı kelime ve ayırıcı segmentlere bölüp mevcut alt çizgilerle eşleştirir.
  /// Alt çizgi sınırları segment sınırlarıyla tam hizalanır; böylece çok
  /// kelimeli alt çizgiler boşluklar dahil kesintisiz çizilir.
  static List<ArticleRenderSegment> buildSegments(
    String paragraph,
    List<ArticleUnderline> paragraphUnderlines,
  ) {
    if (paragraph.isEmpty) return const <ArticleRenderSegment>[];

    final sortedUnderlines = List<ArticleUnderline>.from(paragraphUnderlines)
      ..sort((a, b) => a.startOffset.compareTo(b.startOffset));

    final rawTokens = <({int start, int end, bool isWord})>[];
    var cursor = 0;

    for (final match in _wordPattern.allMatches(paragraph)) {
      if (match.start > cursor) {
        rawTokens.add((start: cursor, end: match.start, isWord: false));
      }
      rawTokens.add((start: match.start, end: match.end, isWord: true));
      cursor = match.end;
    }
    if (cursor < paragraph.length) {
      rawTokens.add((start: cursor, end: paragraph.length, isWord: false));
    }

    final segments = <ArticleRenderSegment>[];
    for (final token in rawTokens) {
      // Token içinden geçen alt çizgi sınırlarını bölerek tam hizalama sağla.
      final cutPoints = <int>{token.start, token.end};
      for (final underline in sortedUnderlines) {
        if (underline.startOffset > token.start &&
            underline.startOffset < token.end) {
          cutPoints.add(underline.startOffset);
        }
        if (underline.endOffset > token.start &&
            underline.endOffset < token.end) {
          cutPoints.add(underline.endOffset);
        }
      }

      final sortedCuts = cutPoints.toList()..sort();
      for (var i = 0; i < sortedCuts.length - 1; i++) {
        final segStart = sortedCuts[i];
        final segEnd = sortedCuts[i + 1];
        if (segEnd <= segStart) continue;

        ArticleUnderline? covering;
        for (final underline in sortedUnderlines) {
          if (underline.startOffset <= segStart &&
              underline.endOffset >= segEnd) {
            covering = underline;
            break;
          }
        }

        segments.add(
          ArticleRenderSegment(
            start: segStart,
            end: segEnd,
            text: paragraph.substring(segStart, segEnd),
            isWord: token.isWord,
            underline: covering,
          ),
        );
      }
    }

    return segments;
  }

  /// Verilen karakter konumunu çevreleyen bağlam cümlesini paragraftan çıkarır.
  static String extractContextSentence(String paragraph, int offset) {
    if (paragraph.isEmpty) return '';
    final safeOffset = offset.clamp(0, paragraph.length - 1);

    var start = 0;
    for (var i = safeOffset - 1; i >= 0; i--) {
      if (_sentenceBoundary.hasMatch(paragraph[i])) {
        start = i + 1;
        break;
      }
    }

    var end = paragraph.length;
    for (var i = safeOffset; i < paragraph.length; i++) {
      if (_sentenceBoundary.hasMatch(paragraph[i])) {
        end = i + 1;
        break;
      }
    }

    var sentence = paragraph
        .substring(start, end)
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    if (sentence.length > 260) {
      final localPos = (safeOffset - start).clamp(0, sentence.length);
      final sliceStart = (localPos - 110).clamp(0, sentence.length);
      final sliceEnd = (localPos + 130).clamp(sliceStart, sentence.length);
      sentence = sentence.substring(sliceStart, sliceEnd).trim();
    }

    return sentence;
  }

  /// Yeni bir alt çizgi aralığını mevcut listeye ekler; aynı paragraftaki
  /// çakışan veya yalnızca boşlukla bitişik aralıkları temiz biçimde birleştirir.
  static List<ArticleUnderline> addAndMergeUnderline({
    required List<ArticleUnderline> existing,
    required ArticleUnderline incoming,
    required String paragraphText,
  }) {
    if (incoming.endOffset <= incoming.startOffset) {
      return existing;
    }

    final clampedStart = incoming.startOffset.clamp(0, paragraphText.length);
    final clampedEnd = incoming.endOffset.clamp(clampedStart, paragraphText.length);
    if (clampedEnd <= clampedStart) return existing;

    final others = <ArticleUnderline>[];
    final sameParagraph = <ArticleUnderline>[];

    for (final item in existing) {
      if (item.paragraphIndex == incoming.paragraphIndex) {
        sameParagraph.add(item);
      } else {
        others.add(item);
      }
    }

    sameParagraph.add(
      ArticleUnderline(
        articleId: incoming.articleId,
        paragraphIndex: incoming.paragraphIndex,
        startOffset: clampedStart,
        endOffset: clampedEnd,
        createdAt: incoming.createdAt ?? DateTime.now(),
      ),
    );
    sameParagraph.sort((a, b) => a.startOffset.compareTo(b.startOffset));

    final merged = <ArticleUnderline>[];
    for (final item in sameParagraph) {
      if (merged.isEmpty) {
        merged.add(item);
        continue;
      }

      final previous = merged.last;
      final gapText = previous.endOffset < item.startOffset
          ? paragraphText.substring(previous.endOffset, item.startOffset)
          : '';
      final isTouchingOrSpaceOnly = item.startOffset <= previous.endOffset ||
          (gapText.isNotEmpty && gapText.trim().isEmpty);

      if (isTouchingOrSpaceOnly) {
        merged[merged.length - 1] = ArticleUnderline(
          articleId: previous.articleId,
          paragraphIndex: previous.paragraphIndex,
          startOffset: previous.startOffset,
          endOffset: item.endOffset > previous.endOffset
              ? item.endOffset
              : previous.endOffset,
          createdAt: previous.createdAt,
        );
      } else {
        merged.add(item);
      }
    }

    final combined = <ArticleUnderline>[...others, ...merged]
      ..sort((a, b) {
        final pDiff = a.paragraphIndex.compareTo(b.paragraphIndex);
        if (pDiff != 0) return pDiff;
        return a.startOffset.compareTo(b.startOffset);
      });

    return List<ArticleUnderline>.unmodifiable(combined);
  }

  /// Paragraf içindeki belirli bir karakter konumuna denk gelen kelimenin
  /// tam karakter aralığını (`start`, `end`, `text`) döndürür.
  /// Sürüklerken boşluk/noktalama üzerine denk gelinirse 1 karakterlik
  /// komşudaki kelimeye yumuşakça hizalanır.
  static ({int start, int end, String text})? findWordBoundsAtOffset(
    String paragraph,
    int charOffset,
  ) {
    if (paragraph.isEmpty) return null;
    final clamped = charOffset.clamp(0, paragraph.length);

    ({int start, int end, String text})? nearest;
    var nearestDist = 999999;

    for (final match in _wordPattern.allMatches(paragraph)) {
      if (clamped >= match.start && clamped <= match.end) {
        return (
          start: match.start,
          end: match.end,
          text: paragraph.substring(match.start, match.end),
        );
      }
      final dist = clamped < match.start
          ? match.start - clamped
          : clamped - match.end;
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = (
          start: match.start,
          end: match.end,
          text: paragraph.substring(match.start, match.end),
        );
      }
    }

    // Boşluk veya noktalama üzerindeyken yalnızca çok yakındaki (<= 2 karakter)
    // kelimeye yapış; uzak boşluklara dokununca yanlış kelime seçme.
    if (nearest != null && nearestDist <= 2) {
      return nearest;
    }
    return null;
  }

  /// Çok kelimelik bir alt çizgi/işaretleme aralığından yalnızca tek bir
  /// kelimenin (`wordStart..wordEnd`) çizgisini çıkarır; solunda ve sağında
  /// kalan kelimelerin çizgilerini temiz biçimde korur.
  static List<ArticleUnderline> removeWordRangeFromUnderlines({
    required List<ArticleUnderline> existing,
    required int paragraphIndex,
    required int wordStart,
    required int wordEnd,
    required String paragraphText,
  }) {
    if (wordEnd <= wordStart) return existing;
    final updated = <ArticleUnderline>[];

    for (final item in existing) {
      if (item.paragraphIndex != paragraphIndex ||
          !item.overlaps(wordStart, wordEnd)) {
        updated.add(item);
        continue;
      }

      // Sol tarafı kırp ve sondaki boşluk/noktalamaları temizle.
      if (item.startOffset < wordStart) {
        var leftEnd = wordStart.clamp(item.startOffset, paragraphText.length);
        while (leftEnd > item.startOffset &&
            paragraphText[leftEnd - 1].trim().isEmpty) {
          leftEnd--;
        }
        if (leftEnd > item.startOffset) {
          updated.add(
            ArticleUnderline(
              articleId: item.articleId,
              paragraphIndex: item.paragraphIndex,
              startOffset: item.startOffset,
              endOffset: leftEnd,
              createdAt: item.createdAt,
            ),
          );
        }
      }

      // Sağ tarafı kırp ve baştaki boşlukları temizle.
      if (item.endOffset > wordEnd) {
        var rightStart = wordEnd.clamp(0, item.endOffset);
        while (rightStart < item.endOffset &&
            paragraphText[rightStart].trim().isEmpty) {
          rightStart++;
        }
        if (item.endOffset > rightStart) {
          updated.add(
            ArticleUnderline(
              articleId: item.articleId,
              paragraphIndex: item.paragraphIndex,
              startOffset: rightStart,
              endOffset: item.endOffset,
              createdAt: item.createdAt,
            ),
          );
        }
      }
    }

    return List<ArticleUnderline>.unmodifiable(updated);
  }

  /// Seçili düz metni paragraf içinde bularak karakter aralığını döndürür.
  static ({int start, int end})? findSelectionRange(
    String paragraph,
    String selectedPlainText,
  ) {
    final trimmed = selectedPlainText.trim();
    if (trimmed.isEmpty) return null;

    final exactIndex = paragraph.indexOf(trimmed);
    if (exactIndex >= 0) {
      return (start: exactIndex, end: exactIndex + trimmed.length);
    }

    final lowerIndex =
        paragraph.toLowerCase().indexOf(trimmed.toLowerCase());
    if (lowerIndex >= 0) {
      return (start: lowerIndex, end: lowerIndex + trimmed.length);
    }

    return null;
  }
}
