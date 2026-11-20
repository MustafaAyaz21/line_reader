/// Arka plan aramasından dönen tek bir web sonucunu temsil eder.
class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.snippet,
    required this.url,
    required this.source,
  });

  final String title;
  final String snippet;
  final String url;
  final String source;

  /// Kullanıcıya gösterilecek sade alan adı veya kaynak etiketi.
  String get displaySource {
    if (source.trim().isNotEmpty) return source.trim();
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isEmpty) return url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}
