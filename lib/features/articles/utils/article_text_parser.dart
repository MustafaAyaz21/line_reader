import '../models/article_reader_models.dart';

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
