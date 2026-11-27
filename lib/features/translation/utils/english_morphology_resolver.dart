/// Bir İngilizce kelimenin kök (temel) kelimesini ve gramer ilişkisini taşır.
/// Örn: `"bought"` -> `baseWord: "buy"`, `relationLabelTr: "2. / 3. hali"`.
class WordInflectionInfo {
  const WordInflectionInfo({
    required this.baseWord,
    required this.relationLabelTr,
    required this.relationLabelEn,
  });

  final String baseWord;
  final String relationLabelTr;
  final String relationLabelEn;
}

/// Yaygın İngilizce çekim eklerini (-s, -es, -ies, -ed, -ing, -ly, -er, -est,
/// -tion/-sion varyasyonları vb.) ve düzensiz fiil/isim biçimlerini hafif ve
/// hızlı biçimde kök/temel form adaylarına indirgeyen çözümleyici.
abstract final class EnglishMorphologyResolver {
  static final RegExp _edgeNonLetters = RegExp(
    r"^[^\p{L}\p{M}]+|[^\p{L}\p{M}]+$",
    unicode: true,
  );
  static final RegExp _multiSpace = RegExp(r'\s+');
  static final RegExp _vowel = RegExp(r'[aeiou]');

  /// Ham kelimeyi sözlük araması için normalize eder (küçük harf, sade boşluk).
  static String normalize(String raw) {
    final spaced = raw.trim().replaceAll(_multiSpace, ' ');
    if (spaced.isEmpty) return '';
    return spaced
        .replaceAll('’', "'")
        .replaceAll(_edgeNonLetters, '')
        .trim()
        .replaceAll('İ', 'i')
        .toLowerCase();
  }

  /// Verilen kelime için öncelik sırasına göre benzersiz aday formlarını döner.
  /// İlk eleman her zaman kelimenin kendi normalize biçimidir; ardından düzensiz
  /// eşleşmeler ve ek soyma (stemming/lemmatization) adayları gelir.
  static List<String> resolveCandidates(String rawWord) {
    final base = normalize(rawWord);
    if (base.isEmpty) return const <String>[];

    final candidates = <String>[];
    final seen = <String>{};

    void add(String candidate) {
      final clean = candidate.trim();
      if (clean.length < 2) return;
      if (seen.add(clean)) {
        candidates.add(clean);
      }
    }

    add(base);

    // Çok kelimeli ifadelerde son veya ilk kelimenin çekimini de dene (örn: "looks closer" -> "look closer").
    if (base.contains(' ')) {
      final parts = base.split(' ');
      if (parts.length <= 4) {
        final firstStems = _singleWordStems(parts.first);
        for (final stem in firstStems) {
          add(<String>[stem, ...parts.skip(1)].join(' '));
        }
        final lastStems = _singleWordStems(parts.last);
        for (final stem in lastStems) {
          add(<String>[...parts.take(parts.length - 1), stem].join(' '));
        }
      }
      return List<String>.unmodifiable(candidates);
    }

    for (final stem in _singleWordStems(base)) {
      add(stem);
    }

    // İkinci geçiş: çoğul ekli türetilmiş sözcükleri (örn. "decisions" -> "decision" -> "decide",
    // "explorations" -> "exploration" -> "explore") temel fiil/sıfat köküne indirge.
    final firstPassSnapshot = List<String>.from(candidates.skip(1));
    for (final intermediate in firstPassSnapshot) {
      if (intermediate.length < 5) continue;
      for (final deeper in _singleWordStems(intermediate)) {
        add(deeper);
      }
    }

    return List<String>.unmodifiable(candidates);
  }

  static List<String> _singleWordStems(String word) {
    final results = <String>[];
    final seen = <String>{word};

    void add(String candidate) {
      if (candidate.length < 2) return;
      if (seen.add(candidate)) {
        results.add(candidate);
      }
    }

    // 1) İyelik veya kısaltma son ekleri ('s, n't)
    if (word.endsWith("'s") && word.length > 3) {
      final stripped = word.substring(0, word.length - 2);
      add(stripped);
      for (final nested in _singleWordStems(stripped)) {
        add(nested);
      }
    }
    if (word.endsWith("n't") && word.length > 4) {
      final contractionBase = _negationContractions[word];
      if (contractionBase != null) {
        add(contractionBase);
      } else {
        add(word.substring(0, word.length - 3));
      }
    }

    // 2) Düzensiz fiiller, isimler ve sıfatlar
    final irregular = _irregularMap[word];
    if (irregular != null) {
      add(irregular);
    }

    // 3) -ies / -ves / -es / -s çoğul ve 3. tekil şahıs ekleri
    if (word.endsWith('ies') && word.length > 4) {
      add('${word.substring(0, word.length - 3)}y');
    }
    if (word.endsWith('ves') && word.length > 4) {
      final stem = word.substring(0, word.length - 3);
      add('${stem}f');
      add('${stem}fe');
    }
    if (word.endsWith('es') && word.length > 3) {
      final withoutEs = word.substring(0, word.length - 2);
      final withoutS = word.substring(0, word.length - 1);
      if (withoutEs.endsWith('s') ||
          withoutEs.endsWith('x') ||
          withoutEs.endsWith('z') ||
          withoutEs.endsWith('ch') ||
          withoutEs.endsWith('sh') ||
          withoutEs.endsWith('o')) {
        add(withoutEs);
        add(withoutS);
      } else {
        add(withoutS);
        add(withoutEs);
      }
    } else if (word.endsWith('s') &&
        !word.endsWith('ss') &&
        !word.endsWith('us') &&
        !word.endsWith('is') &&
        word.length > 3) {
      add(word.substring(0, word.length - 1));
    }

    // 4) -ed geçmiş zaman / sıfat-fiil ekleri
    if (word.endsWith('ied') && word.length > 4) {
      add('${word.substring(0, word.length - 3)}y');
    } else if (word.endsWith('ed') && word.length > 4) {
      final stem = word.substring(0, word.length - 2);
      // Sessiz -e geri getirme (moved -> move, decided -> decide)
      add('${stem}e');
      add(stem);
      if (_hasDoubledConsonant(stem)) {
        add(stem.substring(0, stem.length - 1));
      }
    }

    // 5) -ing şimdiki zaman / isim-fiil ekleri
    if (word.endsWith('ying') && word.length > 5) {
      add('${word.substring(0, word.length - 4)}ie');
      add('${word.substring(0, word.length - 3)}');
    } else if (word.endsWith('ing') && word.length > 4) {
      final stem = word.substring(0, word.length - 3);
      if (_hasDoubledConsonant(stem)) {
        add(stem.substring(0, stem.length - 1));
      }
      add(stem);
      add('${stem}e');
    }

    // 6) -ly zarf ekleri
    if (word.endsWith('ily') && word.length > 4) {
      add('${word.substring(0, word.length - 3)}y');
    } else if (word.endsWith('ally') && word.length > 5) {
      add(word.substring(0, word.length - 2)); // culturally -> cultural
      add(word.substring(0, word.length - 4)); // basically -> basic
    } else if (word.endsWith('ly') && word.length > 4) {
      final stem = word.substring(0, word.length - 2);
      add(stem);
      if (stem.endsWith('b') || stem.endsWith('p') || stem.endsWith('t')) {
        add('${stem}le'); // simply -> simple, possibly -> possible
      }
    }

    // 7) -er / -est karşılaştırma ve üstünlük ekleri
    if (word.endsWith('ier') && word.length > 4) {
      add('${word.substring(0, word.length - 3)}y');
    } else if (word.endsWith('er') && word.length > 4) {
      final stem = word.substring(0, word.length - 2);
      if (_hasDoubledConsonant(stem)) {
        add(stem.substring(0, stem.length - 1));
      }
      add('${stem}e');
      add(stem);
    }

    if (word.endsWith('iest') && word.length > 5) {
      add('${word.substring(0, word.length - 4)}y');
    } else if (word.endsWith('est') && word.length > 5) {
      final stem = word.substring(0, word.length - 3);
      if (_hasDoubledConsonant(stem)) {
        add(stem.substring(0, stem.length - 1));
      }
      add('${stem}e');
      add(stem);
    }

    // 8) -tion / -sion isimleştirme varyasyonları
    if (word.endsWith('ation') && word.length > 6) {
      final stem = word.substring(0, word.length - 5);
      add('${stem}ate'); // creation -> create, celebration -> celebrate
      add('${stem}e'); // exploration -> explore, preparation -> prepare
      add(stem); // information -> inform
    } else if (word.endsWith('ition') && word.length > 6) {
      final stem = word.substring(0, word.length - 5);
      add('${stem}e'); // definition -> define, competition -> compete
      add('${stem}ite');
      add(stem); // addition -> add
    } else if (word.endsWith('ution') && word.length > 6) {
      final stem = word.substring(0, word.length - 5);
      add('${stem}ve'); // solution -> solve
      add('${stem}ute'); // contribution -> contribute
    } else if (word.endsWith('tion') && word.length > 5) {
      final stem = word.substring(0, word.length - 4);
      add('${stem}t'); // action -> act, connection -> connect
      add('${stem}te'); // relation -> relate
      add(stem);
    } else if (word.endsWith('sion') && word.length > 5) {
      final stem = word.substring(0, word.length - 4);
      add('${stem}de'); // decision -> decide, conclusion -> conclude
      add('${stem}se'); // confusion -> confuse
      add('${stem}s'); // discussion -> discuss, expression -> express
      add('${stem}t'); // permission -> permit
      if (stem.endsWith('s')) {
        add('${stem.substring(0, stem.length - 1)}t'); // permission -> permit
      }
    }

    // 9) -ment / -ness / -ity yaygın türetim ekleri
    if (word.endsWith('ment') && word.length > 6) {
      final stem = word.substring(0, word.length - 4);
      add(stem);
      add('${stem}e');
    }
    if (word.endsWith('iness') && word.length > 6) {
      add('${word.substring(0, word.length - 5)}y');
    } else if (word.endsWith('ness') && word.length > 6) {
      add(word.substring(0, word.length - 4));
    }
    if (word.endsWith('ility') && word.length > 6) {
      add('${word.substring(0, word.length - 5)}le'); // ability -> able
    } else if (word.endsWith('ity') && word.length > 5) {
      final stem = word.substring(0, word.length - 3);
      add(stem);
      add('${stem}e'); // activity -> active
    }

    return results;
  }

  static bool _hasDoubledConsonant(String stem) {
    if (stem.length < 3) return false;
    final last = stem[stem.length - 1];
    final prev = stem[stem.length - 2];
    if (last != prev) return false;
    return !_vowel.hasMatch(last);
  }

  static const Map<String, String> _negationContractions = <String, String>{
    "can't": 'can',
    "won't": 'will',
    "shan't": 'shall',
    "don't": 'do',
    "doesn't": 'do',
    "didn't": 'do',
    "isn't": 'be',
    "aren't": 'be',
    "wasn't": 'be',
    "weren't": 'be',
    "haven't": 'have',
    "hasn't": 'have',
    "hadn't": 'have',
    "wouldn't": 'will',
    "couldn't": 'can',
    "shouldn't": 'shall',
  };

  /// Yaygın düzensiz fiil, isim ve sıfat eşleşmeleri.
  static const Map<String, String> _irregularMap = <String, String>{
    // Be / Have / Do / Modals
    'am': 'be',
    'is': 'be',
    'are': 'be',
    'was': 'be',
    'were': 'be',
    'been': 'be',
    'being': 'be',
    'has': 'have',
    'had': 'have',
    'does': 'do',
    'did': 'do',
    'done': 'do',
    'could': 'can',
    'would': 'will',
    'should': 'shall',
    'might': 'may',

    // Düzensiz fiiller
    'arose': 'arise',
    'arisen': 'arise',
    'ate': 'eat',
    'eaten': 'eat',
    'awoke': 'awake',
    'awoken': 'awake',
    'became': 'become',
    'began': 'begin',
    'begun': 'begin',
    'bent': 'bend',
    'bit': 'bite',
    'bitten': 'bite',
    'bled': 'bleed',
    'blew': 'blow',
    'blown': 'blow',
    'bore': 'bear',
    'born': 'bear',
    'borne': 'bear',
    'bought': 'buy',
    'bound': 'bind',
    'bred': 'breed',
    'broke': 'break',
    'broken': 'break',
    'brought': 'bring',
    'built': 'build',
    'burnt': 'burn',
    'caught': 'catch',
    'chose': 'choose',
    'chosen': 'choose',
    'came': 'come',
    'crept': 'creep',
    'dealt': 'deal',
    'dug': 'dig',
    'drank': 'drink',
    'drunk': 'drink',
    'dreamt': 'dream',
    'drew': 'draw',
    'drawn': 'draw',
    'drove': 'drive',
    'driven': 'drive',
    'fell': 'fall',
    'fallen': 'fall',
    'fed': 'feed',
    'felt': 'feel',
    'fled': 'flee',
    'flew': 'fly',
    'flown': 'fly',
    'forbade': 'forbid',
    'forbidden': 'forbid',
    'forgot': 'forget',
    'forgotten': 'forget',
    'forgave': 'forgive',
    'forgiven': 'forgive',
    'fought': 'fight',
    'found': 'find',
    'froze': 'freeze',
    'frozen': 'freeze',
    'gave': 'give',
    'given': 'give',
    'got': 'get',
    'gotten': 'get',
    'grew': 'grow',
    'grown': 'grow',
    'heard': 'hear',
    'held': 'hold',
    'hid': 'hide',
    'hidden': 'hide',
    'hung': 'hang',
    'kept': 'keep',
    'knew': 'know',
    'known': 'know',
    'laid': 'lay',
    'lain': 'lie',
    'lay': 'lie',
    'learnt': 'learn',
    'led': 'lead',
    'left': 'leave',
    'lent': 'lend',
    'lit': 'light',
    'lost': 'lose',
    'made': 'make',
    'meant': 'mean',
    'met': 'meet',
    'paid': 'pay',
    'proven': 'prove',
    'ran': 'run',
    'rang': 'ring',
    'rung': 'ring',
    'rode': 'ride',
    'ridden': 'ride',
    'rose': 'rise',
    'risen': 'rise',
    'said': 'say',
    'sang': 'sing',
    'sung': 'sing',
    'sank': 'sink',
    'sunk': 'sink',
    'sat': 'sit',
    'saw': 'see',
    'seen': 'see',
    'sent': 'send',
    'shook': 'shake',
    'shaken': 'shake',
    'shone': 'shine',
    'shot': 'shoot',
    'shown': 'show',
    'shrank': 'shrink',
    'shrunk': 'shrink',
    'slept': 'sleep',
    'slid': 'slide',
    'sold': 'sell',
    'sought': 'seek',
    'spent': 'spend',
    'spelt': 'spell',
    'spoilt': 'spoil',
    'spoke': 'speak',
    'spoken': 'speak',
    'spun': 'spin',
    'stole': 'steal',
    'stolen': 'steal',
    'stood': 'stand',
    'struck': 'strike',
    'stuck': 'stick',
    'stung': 'sting',
    'swam': 'swim',
    'swum': 'swim',
    'swept': 'sweep',
    'swore': 'swear',
    'sworn': 'swear',
    'swung': 'swing',
    'taught': 'teach',
    'threw': 'throw',
    'thrown': 'throw',
    'thought': 'think',
    'told': 'tell',
    'took': 'take',
    'taken': 'take',
    'tore': 'tear',
    'torn': 'tear',
    'understood': 'understand',
    'went': 'go',
    'gone': 'go',
    'wept': 'weep',
    'woke': 'wake',
    'woken': 'wake',
    'won': 'win',
    'wore': 'wear',
    'worn': 'wear',
    'wound': 'wind',
    'wrote': 'write',
    'written': 'write',

    // Düzensiz isimler
    'children': 'child',
    'men': 'man',
    'women': 'woman',
    'people': 'person',
    'feet': 'foot',
    'teeth': 'tooth',
    'geese': 'goose',
    'mice': 'mouse',
    'oxen': 'ox',
    'leaves': 'leaf',
    'lives': 'life',
    'knives': 'knife',
    'wives': 'wife',
    'wolves': 'wolf',
    'halves': 'half',
    'shelves': 'shelf',
    'thieves': 'thief',
    'loaves': 'loaf',
    'calves': 'calf',
    'scarves': 'scarf',
    'selves': 'self',
    'analyses': 'analysis',
    'crises': 'crisis',
    'theses': 'thesis',
    'phenomena': 'phenomenon',
    'criteria': 'criterion',
    'data': 'datum',
    'media': 'medium',
    'cacti': 'cactus',
    'fungi': 'fungus',
    'alumni': 'alumnus',
    'indices': 'index',
    'appendices': 'appendix',

    // Düzensiz sıfat ve zarflar
    'better': 'good',
    'best': 'good',
    'worse': 'bad',
    'worst': 'bad',
    'farther': 'far',
    'farthest': 'far',
    'further': 'far',
    'furthest': 'far',
    'less': 'little',
    'least': 'little',
    'more': 'much',
    'most': 'much',
    'elder': 'old',
    'eldest': 'old',
  };
}
