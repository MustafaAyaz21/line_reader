import '../../../core/settings/ipa_accent_controller.dart';

/// Bir İngilizce kelimeye ait doğrulanmış Amerikan (US) / İngiliz (UK) IPA
/// okunuşları, İngilizce editoryal tanımı, örnek kullanım cümleleri ile eş ve
/// zıt anlamlı kelimeleri taşıyan zengin sözlük modeli.
class WordLexiconInfo {
  const WordLexiconInfo({
    required this.word,
    this.ipaUs,
    this.ipaUk,
    this.definition,
    this.examples = const <String>[],
    this.synonyms = const <String>[],
    this.antonyms = const <String>[],
  });

  final String word;
  final String? ipaUs;
  final String? ipaUk;
  final String? definition;
  final List<String> examples;
  final List<String> synonyms;
  final List<String> antonyms;

  bool get hasAnyIpa =>
      (ipaUs != null && ipaUs!.trim().isNotEmpty) ||
      (ipaUk != null && ipaUk!.trim().isNotEmpty);

  bool get hasBothIpas =>
      (ipaUs != null && ipaUs!.trim().isNotEmpty) &&
      (ipaUk != null && ipaUk!.trim().isNotEmpty);

  bool get hasDefinition => definition != null && definition!.trim().isNotEmpty;

  bool get hasExamples => examples.isNotEmpty;

  bool get hasRelations => synonyms.isNotEmpty || antonyms.isNotEmpty;

  bool get isEmpty =>
      !hasAnyIpa && !hasRelations && !hasDefinition && !hasExamples;

  /// Kullanıcının seçtiği aksana ait doğrulanmış IPA'yı ve gerçek aksan etiketini
  /// döndürür. Seçili aksan yoksa diğer aksanın doğrulanmış IPA'sını KENDİ
  /// etiketiyle döndürür (asla yanlış aksan etiketi basmaz).
  ({String ipa, IpaAccent accent})? resolveIpa(IpaAccent preferred) {
    final cleanUs = ipaUs?.trim();
    final cleanUk = ipaUk?.trim();
    if (preferred == IpaAccent.us) {
      if (cleanUs != null && cleanUs.isNotEmpty) {
        return (ipa: cleanUs, accent: IpaAccent.us);
      }
      if (cleanUk != null && cleanUk.isNotEmpty) {
        return (ipa: cleanUk, accent: IpaAccent.uk);
      }
    } else {
      if (cleanUk != null && cleanUk.isNotEmpty) {
        return (ipa: cleanUk, accent: IpaAccent.uk);
      }
      if (cleanUs != null && cleanUs.isNotEmpty) {
        return (ipa: cleanUs, accent: IpaAccent.us);
      }
    }
    return null;
  }

  WordLexiconInfo mergeWith(WordLexiconInfo other) {
    final mergedUs = (ipaUs != null && ipaUs!.trim().isNotEmpty)
        ? ipaUs!.trim()
        : (other.ipaUs?.trim().isNotEmpty == true ? other.ipaUs!.trim() : null);
    final mergedUk = (ipaUk != null && ipaUk!.trim().isNotEmpty)
        ? ipaUk!.trim()
        : (other.ipaUk?.trim().isNotEmpty == true ? other.ipaUk!.trim() : null);

    final mergedDef = (definition != null && definition!.trim().isNotEmpty)
        ? definition!.trim()
        : (other.definition?.trim().isNotEmpty == true
            ? other.definition!.trim()
            : null);

    final mergedExamples = _mergeTerms(examples, other.examples, maxCount: 3);
    final mergedSyn = _mergeTerms(synonyms, other.synonyms, maxCount: 6);
    final mergedAnt = _mergeTerms(antonyms, other.antonyms, maxCount: 5);

    return WordLexiconInfo(
      word: word,
      ipaUs: mergedUs,
      ipaUk: mergedUk,
      definition: mergedDef,
      examples: mergedExamples,
      synonyms: mergedSyn,
      antonyms: mergedAnt,
    );
  }

  static List<String> _mergeTerms(
    List<String> primary,
    List<String> extra, {
    required int maxCount,
  }) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in <String>[...primary, ...extra]) {
      final clean = raw.trim().toLowerCase();
      if (clean.isEmpty || !seen.add(clean)) continue;
      result.add(clean);
      if (result.length >= maxCount) break;
    }
    return List<String>.unmodifiable(result);
  }
}
