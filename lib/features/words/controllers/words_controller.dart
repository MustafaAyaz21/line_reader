import 'package:flutter/foundation.dart';

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
  }) async {
    try {
      await _repository.createList(name: name, colorValue: colorValue);
      await loadLists();
      return null;
    } on FormatException catch (error) {
      return error.message;
    } catch (error) {
      debugPrint('[WordsController] Liste olusturulamadi: $error');
      return 'Liste oluşturulurken bir sorun oluştu.';
    }
  }

  /// Mevcut bir listenin rengini (ve özel liste ise adını) günceller.
  Future<String?> updateList({
    required WordList list,
    required String name,
    required int colorValue,
  }) async {
    try {
      await _repository.updateList(
        id: list.id,
        name: name,
        colorValue: colorValue,
        isDefault: list.isDefault,
      );
      await loadLists();
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
      await _repository.deleteList(listId);
      _wordsByList?.remove(listId);
      await loadLists();
    } catch (error) {
      debugPrint('[WordsController] Liste silinemedi: $error');
      _errorMessage = 'Liste silinirken bir sorun oluştu.';
      _safeNotifyListeners();
    }
  }

  /// Kelimeyi seçilen listeye (belirtilmezse varsayılan "Favoriler" listesine) kaydeder.
  Future<SaveWordStatus> addWord({
    required String word,
    required String meaning,
    List<MeaningEntry> meanings = const <MeaningEntry>[],
    int? listId,
  }) async {
    try {
      final targetListId =
          listId ?? defaultList?.id ?? await _repository.getDefaultFavoritesListId();

      final status = await _repository.saveWord(
        listId: targetListId,
        word: word,
        meaning: meaning,
        meanings: meanings,
      );

      if (status == SaveWordStatus.saved) {
        await Future.wait<void>(<Future<void>>[
          loadLists(),
          loadWordsForList(targetListId),
        ]);
      }
      return status;
    } catch (error) {
      debugPrint('[WordsController] Kelime kaydedilemedi: $error');
      return SaveWordStatus.error;
    }
  }

  Future<void> removeWord(SavedWord item) async {
    final id = item.id;
    if (id == null) return;
    try {
      await _repository.deleteWord(id);
      await Future.wait<void>(<Future<void>>[
        loadLists(),
        loadWordsForList(item.listId),
      ]);
    } catch (error) {
      debugPrint('[WordsController] Kelime silinemedi: $error');
      _errorMessage = 'Kelime silinirken bir sorun oluştu.';
      _safeNotifyListeners();
    }
  }
}
