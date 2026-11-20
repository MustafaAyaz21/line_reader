import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/web_search_result.dart';

/// Arama sorgularını ekranda Google web arayüzü göstermeden arka planda
/// çalıştıran ve sonuçları başlık, kısa özet ve kaynak/URL olarak döndüren servis.
class WebSearchService {
  WebSearchService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxResults = 16;

  static const Map<String, String> _defaultHeaders = <String, String>{
    'Accept': 'text/html,application/xhtml+xml,application/xml,application/json;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,tr;q=0.8',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
  };

  final http.Client _httpClient;
  final bool _ownsClient;

  Future<List<WebSearchResult>> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const <WebSearchResult>[];

    // Birden fazla açık arama kaynağını paralel çalıştırarak hızlı ve zengin
    // sonuç listesi oluştur (hiçbir dış arama sayfası ekrana basılmaz).
    final buckets = await Future.wait<List<WebSearchResult>>(
      <Future<List<WebSearchResult>>>[
        _searchDuckDuckGoHtml(query),
        _searchWikipedia(query),
        _searchGoogleNewsRss(query),
        _searchDuckDuckGoInstant(query),
      ],
    );

    final merged = <WebSearchResult>[];
    final seenUrls = <String>{};
    final seenTitles = <String>{};

    void addAll(List<WebSearchResult> items, {int? limit}) {
      var added = 0;
      for (final item in items) {
        if (merged.length >= _maxResults) break;
        if (limit != null && added >= limit) break;

        final normUrl = _normalizeUrlKey(item.url);
        final normTitle = item.title.trim().toLowerCase();
        if (normUrl.isEmpty || normTitle.isEmpty) continue;
        if (!seenUrls.add(normUrl)) continue;
        if (!seenTitles.add(normTitle)) continue;

        merged.add(item);
        added++;
      }
    }

    // 1) Genel web sonuçları (en fazla 8)
    addAll(buckets[0], limit: 8);
    // 2) Ansiklopedik / okuma odaklı Wikipedia sonuçları (en fazla 4)
    addAll(buckets[1], limit: 4);
    // 3) Güncel Google haber/makale RSS sonuçları (en fazla 6)
    addAll(buckets[2], limit: 6);
    // 4) Anlık bilgi / ilgili kaynaklar
    addAll(buckets[3], limit: 4);
    // Kalan kontenjan varsa diğer sonuçlarla tamamla
    for (final bucket in buckets) {
      addAll(bucket);
    }

    return merged;
  }

  /// DuckDuckGo hafif HTML sonucunu arka planda ayrıştırır (genel web bağlantıları).
  Future<List<WebSearchResult>> _searchDuckDuckGoHtml(String query) async {
    final uri = Uri.https('html.duckduckgo.com', '/html/', <String, String>{
      'q': query,
    });

    try {
      final response =
          await _httpClient.get(uri, headers: _defaultHeaders).timeout(_timeout);
      if (response.statusCode != 200) return const <WebSearchResult>[];

      final body = response.body;
      final linkMatches = RegExp(
        r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>',
        caseSensitive: false,
      ).allMatches(body).toList();

      if (linkMatches.isEmpty) return const <WebSearchResult>[];

      final snippetMatches = RegExp(
        r'<(?:a|div)[^>]*class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)</(?:a|div)>',
        caseSensitive: false,
      ).allMatches(body).toList();

      final results = <WebSearchResult>[];
      for (var i = 0; i < linkMatches.length && results.length < 10; i++) {
        final rawHref = _decodeHtmlEntities(linkMatches[i].group(1) ?? '');
        final resolvedUrl = _resolveDuckDuckGoRedirect(rawHref);
        if (resolvedUrl == null) continue;

        final title = _cleanHtmlText(linkMatches[i].group(2) ?? '');
        if (title.isEmpty) continue;

        final snippet = i < snippetMatches.length
            ? _cleanHtmlText(snippetMatches[i].group(1) ?? '')
            : '';

        results.add(
          WebSearchResult(
            title: title,
            snippet: snippet.isNotEmpty
                ? snippet
                : 'Sayfayı Line Reader içinde açmak için dokunun.',
            url: resolvedUrl,
            source: _extractHost(resolvedUrl),
          ),
        );
      }
      return results;
    } on SocketException catch (error) {
      debugPrint('[WebSearchService] DuckDuckGo HTML ag hatasi: $error');
      return const <WebSearchResult>[];
    } catch (error) {
      debugPrint('[WebSearchService] DuckDuckGo HTML hatasi: $error');
      return const <WebSearchResult>[];
    }
  }

  /// Wikipedia açık JSON arama API'si (İngilizce ve Türkçe sorgu destekli).
  Future<List<WebSearchResult>> _searchWikipedia(String query) async {
    final isTurkish = RegExp(r'[çğıöşüÇĞİÖŞÜ]').hasMatch(query);
    final host = isTurkish ? 'tr.wikipedia.org' : 'en.wikipedia.org';

    final uri = Uri.https(host, '/w/api.php', <String, String>{
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'format': 'json',
      'srlimit': '5',
      'utf8': '1',
    });

    try {
      final response =
          await _httpClient.get(uri, headers: _defaultHeaders).timeout(_timeout);
      if (response.statusCode != 200) return const <WebSearchResult>[];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) return const <WebSearchResult>[];
      final queryObj = decoded['query'];
      if (queryObj is! Map<String, Object?>) return const <WebSearchResult>[];
      final list = queryObj['search'];
      if (list is! List<Object?>) return const <WebSearchResult>[];

      final results = <WebSearchResult>[];
      for (final item in list) {
        if (item is! Map<String, Object?>) continue;
        final title = (item['title'] as String?)?.trim() ?? '';
        if (title.isEmpty) continue;

        final rawSnippet = (item['snippet'] as String?) ?? '';
        final cleanSnippet = _cleanHtmlText(rawSnippet);
        final pageSlug = Uri.encodeComponent(title.replaceAll(' ', '_'));
        final pageUrl = 'https://$host/wiki/$pageSlug';

        results.add(
          WebSearchResult(
            title: title,
            snippet: cleanSnippet.isNotEmpty
                ? '$cleanSnippet...'
                : 'Wikipedia makalesini okumak için dokunun.',
            url: pageUrl,
            source: host,
          ),
        );
      }
      return results;
    } catch (error) {
      debugPrint('[WebSearchService] Wikipedia arama hatasi: $error');
      return const <WebSearchResult>[];
    }
  }

  /// Google News RSS arama beslemesini arka planda çeker (Google web UI göstermez).
  Future<List<WebSearchResult>> _searchGoogleNewsRss(String query) async {
    final isTurkish = RegExp(r'[çğıöşüÇĞİÖŞÜ]').hasMatch(query);
    final uri = Uri.https('news.google.com', '/rss/search', <String, String>{
      'q': query,
      'hl': isTurkish ? 'tr' : 'en-US',
      'gl': isTurkish ? 'TR' : 'US',
      'ceid': isTurkish ? 'TR:tr' : 'US:en',
    });

    try {
      final response =
          await _httpClient.get(uri, headers: _defaultHeaders).timeout(_timeout);
      if (response.statusCode != 200) return const <WebSearchResult>[];

      final itemMatches = RegExp(
        r'<item>([\s\S]*?)</item>',
        caseSensitive: false,
      ).allMatches(response.body);

      final results = <WebSearchResult>[];
      for (final match in itemMatches) {
        if (results.length >= 6) break;
        final block = match.group(1) ?? '';

        final rawTitle = _extractXmlTag(block, 'title');
        final rawLink = _extractXmlTag(block, 'link');
        final rawSource = _extractXmlTag(block, 'source');
        final rawDesc = _extractXmlTag(block, 'description');

        final url = _decodeHtmlEntities(rawLink).trim();
        if (url.isEmpty || !url.startsWith('http')) continue;

        var title = _cleanHtmlText(rawTitle);
        final source = _cleanHtmlText(rawSource);
        if (source.isNotEmpty && title.endsWith(' - $source')) {
          title = title.substring(0, title.length - ' - $source'.length).trim();
        }
        if (title.isEmpty) continue;

        final cleanDesc = _cleanHtmlText(rawDesc);
        final snippet = (cleanDesc.isNotEmpty && cleanDesc != title)
            ? cleanDesc
            : (source.isNotEmpty
                ? '$source kaynağındaki makaleyi okumak için dokunun.'
                : 'Haberi/makaleyi okumak için dokunun.');

        results.add(
          WebSearchResult(
            title: title,
            snippet: snippet,
            url: url,
            source: source.isNotEmpty ? source : _extractHost(url),
          ),
        );
      }

      return results;
    } catch (error) {
      debugPrint('[WebSearchService] Google News RSS hatasi: $error');
      return const <WebSearchResult>[];
    }
  }

  /// DuckDuckGo Instant Answer JSON API'sinden özet ve ilgili kaynakları çeker.
  Future<List<WebSearchResult>> _searchDuckDuckGoInstant(String query) async {
    final uri = Uri.https('api.duckduckgo.com', '/', <String, String>{
      'q': query,
      'format': 'json',
      'no_html': '1',
      'skip_disambig': '1',
    });

    try {
      final response =
          await _httpClient.get(uri, headers: _defaultHeaders).timeout(_timeout);
      if (response.statusCode != 200) return const <WebSearchResult>[];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) return const <WebSearchResult>[];

      final results = <WebSearchResult>[];

      final abstractUrl = (decoded['AbstractURL'] as String?)?.trim() ?? '';
      final heading = (decoded['Heading'] as String?)?.trim() ?? '';
      final abstractText = (decoded['AbstractText'] as String?)?.trim() ?? '';
      final abstractSource =
          (decoded['AbstractSource'] as String?)?.trim() ?? '';

      if (abstractUrl.startsWith('http') && heading.isNotEmpty) {
        results.add(
          WebSearchResult(
            title: heading,
            snippet: abstractText.isNotEmpty
                ? abstractText
                : 'Kaynağı açmak için dokunun.',
            url: abstractUrl,
            source: abstractSource.isNotEmpty
                ? abstractSource
                : _extractHost(abstractUrl),
          ),
        );
      }

      final related = decoded['RelatedTopics'];
      if (related is List<Object?>) {
        for (final entry in related) {
          if (results.length >= 4) break;
          if (entry is! Map<String, Object?>) continue;
          final firstUrl = (entry['FirstURL'] as String?)?.trim() ?? '';
          final text = (entry['Text'] as String?)?.trim() ?? '';
          if (!firstUrl.startsWith('http') || text.isEmpty) continue;

          final parts = text.split(' - ');
          final title = parts.first.trim();
          final snippet =
              parts.length > 1 ? parts.sublist(1).join(' - ').trim() : text;

          results.add(
            WebSearchResult(
              title: title,
              snippet: snippet,
              url: firstUrl,
              source: _extractHost(firstUrl),
            ),
          );
        }
      }

      return results;
    } catch (error) {
      debugPrint('[WebSearchService] DuckDuckGo Instant hatasi: $error');
      return const <WebSearchResult>[];
    }
  }

  String? _resolveDuckDuckGoRedirect(String rawHref) {
    final trimmed = rawHref.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.contains('uddg=')) {
      final normalized =
          trimmed.startsWith('//') ? 'https:$trimmed' : trimmed;
      final uri = Uri.tryParse(normalized);
      final target = uri?.queryParameters['uddg'];
      if (target != null && target.startsWith('http')) {
        return target;
      }
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return null;
  }

  String _extractXmlTag(String block, String tag) {
    final match = RegExp(
      '<$tag[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(block);
    var value = match?.group(1) ?? '';
    if (value.startsWith('<![CDATA[') && value.endsWith(']]>')) {
      value = value.substring(9, value.length - 3);
    }
    return value;
  }

  String _cleanHtmlText(String raw) {
    final decoded = _decodeHtmlEntities(raw);
    final withoutTags = decoded.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return _decodeHtmlEntities(withoutTags)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _decodeHtmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }

  String _extractHost(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isEmpty) return '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  String _normalizeUrlKey(String url) {
    final trimmed = url.trim().toLowerCase();
    if (trimmed.endsWith('/') && trimmed.length > 8) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}
