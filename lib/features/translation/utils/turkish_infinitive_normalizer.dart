/// Türkçe çeviri metnini sadeleştirir ve fiil sonuçlarının zaman eki olmadan
/// mastar (`-mak/-mek`) biçiminde kalmasını sağlar.
abstract final class TurkishInfinitiveNormalizer {
  static final RegExp _parentheticalPos = RegExp(
    r'\s*\((?:noun|verb|adjective|adverb|isim|fiil|sıfat|zarf)\)\s*',
    caseSensitive: false,
  );
  static final RegExp _edgePunctuation = RegExp(r'^[.,;:!?“”"\x27]+|[.,;:!?“”"\x27]+$');
  static final RegExp _multiWhitespace = RegExp(r'\s+');

  /// Ham çeviri metnini temizler; `isVerb` true ise mastar son ekini düzenler.
  static String normalize(String rawText, {required bool isVerb}) {
    var text = rawText
        .replaceAll(_parentheticalPos, ' ')
        .trim()
        .replaceAll(_multiWhitespace, ' ')
        .replaceAll(_edgePunctuation, '')
        .trim();

    if (text.isEmpty) return '';

    text = text.replaceAll('İ', 'i').toLowerCase();

    // Birden fazla alternatif geldiyse ilk en sade anlamı al.
    if (text.contains(',')) {
      text = text.split(',').first.trim();
    } else if (text.contains(';')) {
      text = text.split(';').first.trim();
    }

    if (!isVerb) {
      return text;
    }

    // "to <verb>" çevirilerinde sık görülen "için" / "-makta/-mekte" kalıplarını
    // kayıpsız şekilde yalın mastar (-mak/-mek) biçimine indirge.
    if (text.endsWith('mak için')) {
      return text.substring(0, text.length - ' için'.length).trim();
    }
    if (text.endsWith('mek için')) {
      return text.substring(0, text.length - ' için'.length).trim();
    }
    if (text.endsWith('maktadır')) {
      return '${text.substring(0, text.length - 'maktadır'.length)}mak';
    }
    if (text.endsWith('mektedir')) {
      return '${text.substring(0, text.length - 'mektedir'.length)}mek';
    }
    if (text.endsWith('makta')) {
      return '${text.substring(0, text.length - 'makta'.length)}mak';
    }
    if (text.endsWith('mekte')) {
      return '${text.substring(0, text.length - 'mekte'.length)}mek';
    }
    if (text.endsWith('maya')) {
      return '${text.substring(0, text.length - 'maya'.length)}mak';
    }
    if (text.endsWith('meye')) {
      return '${text.substring(0, text.length - 'meye'.length)}mek';
    }

    return text;
  }
}
