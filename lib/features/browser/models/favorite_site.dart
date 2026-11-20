/// Tarayıcıda kullanıcının favorilere kaydettiği web sitesi modeli.
class FavoriteSite {
  const FavoriteSite({
    this.id,
    required this.title,
    required this.url,
    required this.createdAt,
  });

  final int? id;
  final String title;
  final String url;
  final DateTime createdAt;

  /// Kısa alan adı gösterimi (ör. `www.bbc.com` -> `bbc.com`).
  String get displayHost {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isEmpty) return url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// Boş başlık gelirse alan adını dönen kısa etiket.
  String get displayTitle {
    final trimmed = title.trim();
    return trimmed.isNotEmpty ? trimmed : displayHost;
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      'title': displayTitle,
      'url': url,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory FavoriteSite.fromMap(Map<String, Object?> map) {
    return FavoriteSite(
      id: map['id'] as int?,
      title: map['title'] as String,
      url: map['url'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
      ),
    );
  }
}
