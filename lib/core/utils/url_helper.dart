/// Adres çubuğuna girilen metnin doğrudan bir web adresi (URL/alan adı)
/// olup olmadığını çözümler.
abstract final class UrlHelper {
  /// Girdi geçerli bir web adresi veya alan adıysa `Uri` döner;
  /// arama metniyse `null` döner (böylece uygulama içi arka plan arama çalışır).
  static Uri? tryParseDirectUrl(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final hasScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');
    if (hasScheme) {
      final parsed = Uri.tryParse(trimmed);
      if (parsed != null && parsed.hasAuthority && parsed.host.isNotEmpty) {
        return parsed;
      }
      return null;
    }

    final looksLikeDomain = !trimmed.contains(' ') &&
        trimmed.contains('.') &&
        !trimmed.startsWith('.') &&
        !trimmed.endsWith('.');
    if (looksLikeDomain) {
      final parsed = Uri.tryParse('https://$trimmed');
      if (parsed != null && parsed.host.contains('.')) {
        return parsed;
      }
    }

    return null;
  }

  /// Favori site gibi doğrudan URL açma noktaları için yardımcı.
  static Uri? resolveInput(String rawInput) => tryParseDirectUrl(rawInput);
}
