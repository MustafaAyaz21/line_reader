import 'package:flutter/foundation.dart';

import '../../../core/sync/cloud_sync_service.dart';
import '../../translation/models/word_meaning.dart';
import '../data/word_repository.dart';
import '../models/saved_word.dart';
import '../models/word_list.dart';

/// Özel kelime listelerini ve her listenin kayıtlı kelimelerini yönetir.
class WordsController extends ChangeNotifier {
  WordsController(this._repository);

  final WordRepository _repository;

  List<WordList>? _lists;
  Map<int, List<SavedWord>>? _wordsByList;
  bool _isLoading = false;
  bool _isDisposed = false;
  String? _errorMessage;

  List<WordList> get lists =>
      List<WordList>.unmodifiable(_lists ?? const <WordList>[]);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  WordList? get defaultList {
    final current = _lists;
    if (current == null || current.isEmpty) return null;
    for (final item in current) {
      if (item.isDefault) return item;
    }
    return current.first;
  }

  WordList? findListById(int listId) {
    final current = _lists;
    if (current == null) return null;
    for (final item in current) {
      if (item.id == listId) return item;
    }
    return null;
  }

  List<SavedWord> wordsForList(int listId) {
    final map = _wordsByList;
    if (map == null) return const <SavedWord>[];
    return List<SavedWord>.unmodifiable(map[listId] ?? const <SavedWord>[]);
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Tüm kelime listelerini (ve varsayılan "Favoriler" listesini) yükler.
  Future<List<WordList>> loadLists() async {
    _isLoading = true;
    _errorMessage = null;
    _safeNotifyListeners();

    try {
      final loaded = await _repository.getAllLists();
      _lists = loaded;
      return loaded;
    } catch (error) {
      debugPrint('[WordsController] Listeler yuklenemedi: $error');
      _errorMessage = 'Kelime listeleri yüklenirken bir sorun oluştu.';
      return lists;
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Eski çağrı noktalarıyla uyumluluk için listeleri yeniler.
  Future<void> loadWords() async {
    await loadLists();
  }

  /// Bulut senkronizasyonu sonrası hem tüm listeleri hem de önbellekteki
  /// liste kelimelerini (ve varsayılan listeyi) SQLite'tan yeniden yükler.
  Future<void> reloadAll() async {
    final loaded = await loadLists();
    final idsToReload = <int>{
      ...?_wordsByList?.keys,
      for (final item in loaded)
        if (item.id != null) item.id!,
    };
    for (final listId in idsToReload) {
      await loadWordsForList(listId);
    }
  }

  /// Belirli bir listeye ait kelimeleri SQLite'tan yükler.
  Future<List<SavedWord>> loadWordsForList(int listId) async {
    try {
      final items = await _repository.getWordsByList(listId);
      final map = _wordsByList ??= <int, List<SavedWord>>{};
      map[listId] = items;
      _safeNotifyListeners();
      return items;
    } catch (error) {
      debugPrint('[WordsController] Liste kelimeleri yuklenemedi: $error');
      return wordsForList(listId);
    }
  }

  /// Yeni özel kelime listesi oluşturur. Başarılıysa `null`, hata varsa mesaj döner.
  Future<String?> createList({
    required String name,
    required int colorValue,
    String? icon,
  }) async {
    final result = await createListWithResult(
      name: name,
      colorValue: colorValue,
      icon: icon,
    );
    return result.error;
  }

  /// Yeni özel kelime listesi oluşturur; oluşan [WordList] kaydını (veya hata
  /// mesajını) döndürür ve bellek içi listeyi hemen yeniler.
  Future<({WordList? list, String? error})> createListWithResult({
    required String name,
    required int colorValue,
    String? icon,
  }) async {
    try {
      final created = await _repository.createList(
        name: name,
        colorValue: colorValue,
        icon: icon,
      );
      await CloudSyncService.shared.clearDeletedList(created.name);
      await loadLists();
      CloudSyncService.shared.scheduleSync();
      return (list: created, error: null);
    } on FormatException catch (error) {
      return (list: null, error: error.message);
    } catch (error) {
      debugPrint('[WordsController] Liste olusturulamadi: $error');
      return (
        list: null,
        error: 'Liste oluşturulurken bir sorun oluştu.',
      );
    }
  }

  /// Mevcut bir listenin rengini (ve özel liste ise adını ve logosunu) günceller.
  Future<String?> updateList({
    required WordList list,
    required String name,
    required int colorValue,
    String? icon,
  }) async {
    try {
      await _repository.updateList(
        id: list.id,
        name: name,
        colorValue: colorValue,
        isDefault: list.isDefault,
        icon: icon,
      );
      await loadLists();
      CloudSyncService.shared.scheduleSync();
      return null;
    } on FormatException catch (error) {
      return error.message;
    } catch (error) {
      debugPrint('[WordsController] Liste guncellenemedi: $error');
      return 'Liste güncellenirken bir sorun oluştu.';
    }
  }

  /// Özel bir kelime listesini siler (varsayılan "Favoriler" korunur).
  Future<void> deleteList(int listId) async {
    try {
      String? deletedName;
      for (final item in lists) {
        if (item.id == listId && !item.isDefault) {
          deletedName = item.name;
          break;
        }
      }
      await _repository.deleteList(listId);
      _wordsByList?.remove(listId);
      if (deletedName != null) {
        await CloudSyncService.shared.recordDeletedList(deletedName);
      }
      await loadLists();
      CloudSyncService.shared.scheduleSync();
    } catch (error) {
      debugPrint('[WordsController] Liste silinemedi: $error');
      _errorMessage = 'Liste silinirken bir sorun oluştu.';
      _safeNotifyListeners();
    }
  }

  /// Belirli bir listede verilen kelimenin mevcut kayıtlarını döner.
  Future<List<SavedWord>> findExistingWordsInList({
    required int listId,
    required String word,
  }) async {
    try {
      return await _repository.findWordsInList(listId: listId, word: word);
    } catch (error) {
      debugPrint('[WordsController] Kayitli kelime sorgulanamadi: $error');
      return const <SavedWord>[];
    }
  }

  /// Kelimeyi seçilen listeye (belirtilmezse varsayılan "Favoriler" listesine) kaydeder.
  Future<SaveWordStatus> addWord({
    required String word,
    required String meaning,
    List<MeaningEntry> meanings = const <MeaningEntry>[],
    String? ipaUs,
    String? ipaUk,
    List<String> synonyms = const <String>[],
    List<String> antonyms = const <String>[],
    int? listId,
    bool allowDuplicate = false,
  }) async {
    try {
      final targetListId =
          listId ?? defaultList?.id ?? await _repository.getDefaultFavoritesListId();

      final status = await _repository.saveWord(
        listId: targetListId,
        word: word,
        meaning: meaning,
        meanings: meanings,
        ipaUs: ipaUs,
        ipaUk: ipaUk,
        synonyms: synonyms,
        antonyms: antonyms,
        allowDuplicate: allowDuplicate,
      );

      if (status == SaveWordStatus.saved) {
        final targetListName = lists
                .where((l) => l.id == targetListId)
                .map((l) => l.name)
                .firstOrNull ??
            'Favoriler';
        await CloudSyncService.shared.clearDeletedWord(
          listName: targetListName,
          word: word,
        );
        await Future.wait<void>(<Future<void>>[
          loadLists(),
          loadWordsForList(targetListId),
        ]);
        CloudSyncService.shared.scheduleSync();
      }
      return status;
    } catch (error) {
      debugPrint('[WordsController] Kelime kaydedilemedi: $error');
      return SaveWordStatus.error;
    }
  }

  /// Mevcut bir kelime kaydının anlamlarını günceller (veya anlam kalmadıysa siler).
  Future<SaveWordStatus> updateWordMeanings({
    required SavedWord existingWord,
    required List<MeaningEntry> meanings,
    String? ipaUs,
    String? ipaUk,
    List<String>? synonyms,
    List<String>? antonyms,
  }) async {
    try {
      final status = await _repository.updateWordMeanings(
        existingWord: existingWord,
        meanings: meanings,
        ipaUs: ipaUs,
        ipaUk: ipaUk,
        synonyms: synonyms,
        antonyms: antonyms,
      );
      if (status == SaveWordStatus.saved) {
        if (meanings.isEmpty) {
          final targetListName = lists
                  .where((l) => l.id == existingWord.listId)
                  .map((l) => l.name)
                  .firstOrNull ??
              'Favoriler';
          await CloudSyncService.shared.recordDeletedWord(
            listName: targetListName,
            word: existingWord.word,
          );
        }
        await Future.wait<void>(<Future<void>>[
          loadLists(),
          loadWordsForList(existingWord.listId),
        ]);
        CloudSyncService.shared.scheduleSync();
      }
      return status;
    } catch (error) {
      debugPrint('[WordsController] Kelime anlamlari guncellenemedi: $error');
      return SaveWordStatus.error;
    }
  }

  Future<void> removeWord(SavedWord item) async {
    final id = item.id;
    if (id == null) return;
    try {
      final targetListName = lists
              .where((l) => l.id == item.listId)
              .map((l) => l.name)
              .firstOrNull ??
          'Favoriler';
      await _repository.deleteWord(id);
      await CloudSyncService.shared.recordDeletedWord(
        listName: targetListName,
        word: item.word,
      );
      await Future.wait<void>(<Future<void>>[
        loadLists(),
        loadWordsForList(item.listId),
      ]);
      CloudSyncService.shared.scheduleSync();
    } catch (error) {
      debugPrint('[WordsController] Kelime silinemedi: $error');
      _errorMessage = 'Kelime silinirken bir sorun oluştu.';
      _safeNotifyListeners();
    }
  }
}
