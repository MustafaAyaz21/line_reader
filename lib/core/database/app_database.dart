import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Uygulamanın yerel SQLite veri tabanı bağlantısını ve şema geçişlerini yönetir.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _databaseName = 'linereader.db';
  static const int _databaseVersion = 9;

  static const String wordsTable = 'words';
  static const String wordListsTable = 'word_lists';
  static const String translationCacheTable = 'translation_cache';
  static const String settingsTable = 'app_settings';
  static const String favoriteSitesTable = 'favorite_sites';
  static const String articlesCacheTable = 'articles_cache';

  static const String defaultFavoritesName = 'Favoriler';
  static const int defaultFavoritesColorValue = 0xFFF59E0B;

  Database? _database;
  int _ensuredSchemaVersion = 0;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      if (_ensuredSchemaVersion < _databaseVersion) {
        await _ensureAllTables(existing);
        _ensuredSchemaVersion = _databaseVersion;
      }
      return existing;
    }

    final opened = await _openDatabase();
    _database = opened;
    _ensuredSchemaVersion = _databaseVersion;
    return opened;
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, _databaseName);

    return openDatabase(
      dbPath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _ensureAllTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await ensureTranslationCacheTable(db);
    }
    if (oldVersion < 3) {
      await ensureSettingsTable(db);
    }
    if (oldVersion < 4) {
      await ensureWordListsAndWordsSchema(db);
    }
    if (oldVersion < 5) {
      await ensureTranslationCacheTable(db);
    }
    if (oldVersion < 6) {
      await ensureWordListsAndWordsSchema(db);
    }
    if (oldVersion < 7) {
      await ensureFavoriteSitesTable(db);
    }
    if (oldVersion < 8) {
      await ensureWordListsAndWordsSchema(db);
    }
    if (oldVersion < 9) {
      await ensureArticlesCacheTable(db);
    }
  }

  Future<void> _onOpen(Database db) async {
    await _ensureAllTables(db);
  }

  Future<void> _ensureAllTables(Database db) async {
    await ensureWordListsAndWordsSchema(db);
    await ensureTranslationCacheTable(db);
    await ensureSettingsTable(db);
    await ensureFavoriteSitesTable(db);
    await ensureArticlesCacheTable(db);
  }

  /// `word_lists` tablosunu, varsayılan "Favoriler" listesini ve `words`
  /// tablosunun `list_id` sütununu (eski verileri koruyarak) garanti altına alır.
  Future<int> ensureWordListsAndWordsSchema([Database? existingDb]) async {
    final db = existingDb ?? await database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $wordListsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color_value INTEGER NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    final favoritesId = await _ensureDefaultFavoritesRow(db);

    final tableCheck = await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object>[wordsTable],
    );

    if (tableCheck.isEmpty) {
      await _createWordsTableWithListId(db);
      return favoritesId;
    }

    final tableSql = (tableCheck.first['sql'] as String? ?? '').toUpperCase();
    final hasLegacyUniqueConstraint = tableSql.contains('UNIQUE');
    final columns = await db.rawQuery('PRAGMA table_info($wordsTable)');
    final hasListId = columns.any((col) => col['name'] == 'list_id');
    final hasMeaningsJson = columns.any((col) => col['name'] == 'meanings_json');

    if (!hasListId || hasLegacyUniqueConstraint) {
      // onUpgrade/onOpen zaten bir transaction içinde çalıştığından
      // iç içe `db.transaction` açmadan doğrudan güvenli şema geçişi yap.
      // v8 itibarıyla aynı kelime farklı anlam gruplarıyla birden fazla kez
      // eklenebileceği için UNIQUE(list_id, word) kısıtı kaldırılır.
      await db.execute('DROP TABLE IF EXISTS ${wordsTable}_migrated');
      await db.execute('''
        CREATE TABLE ${wordsTable}_migrated (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          list_id INTEGER NOT NULL,
          word TEXT NOT NULL,
          meaning TEXT NOT NULL,
          meanings_json TEXT,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (list_id) REFERENCES $wordListsTable (id) ON DELETE CASCADE
        )
      ''');

      if (!hasListId) {
        await db.execute(
          '''
          INSERT INTO ${wordsTable}_migrated (id, list_id, word, meaning, created_at)
          SELECT id, ?, word, meaning, created_at FROM $wordsTable
          ''',
          <Object>[favoritesId],
        );
      } else if (hasMeaningsJson) {
        await db.execute('''
          INSERT INTO ${wordsTable}_migrated (id, list_id, word, meaning, meanings_json, created_at)
          SELECT id, list_id, word, meaning, meanings_json, created_at FROM $wordsTable
        ''');
      } else {
        await db.execute('''
          INSERT INTO ${wordsTable}_migrated (id, list_id, word, meaning, created_at)
          SELECT id, list_id, word, meaning, created_at FROM $wordsTable
        ''');
      }

      await db.execute('DROP TABLE $wordsTable');
      await db.execute(
        'ALTER TABLE ${wordsTable}_migrated RENAME TO $wordsTable',
      );
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_words_list_created_at
        ON $wordsTable (list_id, created_at DESC)
      ''');
    } else {
      if (!hasMeaningsJson) {
        await db.execute(
          'ALTER TABLE $wordsTable ADD COLUMN meanings_json TEXT',
        );
      }
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_words_list_created_at
        ON $wordsTable (list_id, created_at DESC)
      ''');
    }

    return favoritesId;
  }

  Future<int> _ensureDefaultFavoritesRow(Database db) async {
    final existingDefault = await db.query(
      wordListsTable,
      where: 'is_default = 1',
      limit: 1,
    );
    if (existingDefault.isNotEmpty) {
      return existingDefault.first['id'] as int;
    }

    final existingByName = await db.query(
      wordListsTable,
      where: 'LOWER(name) = ?',
      whereArgs: <Object>[defaultFavoritesName.toLowerCase()],
      limit: 1,
    );
    if (existingByName.isNotEmpty) {
      final id = existingByName.first['id'] as int;
      await db.update(
        wordListsTable,
        <String, Object?>{'is_default': 1},
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
      return id;
    }

    return db.insert(
      wordListsTable,
      <String, Object?>{
        'name': defaultFavoritesName,
        'color_value': defaultFavoritesColorValue,
        'is_default': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<void> _createWordsTableWithListId(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $wordsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        list_id INTEGER NOT NULL,
        word TEXT NOT NULL,
        meaning TEXT NOT NULL,
        meanings_json TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (list_id) REFERENCES $wordListsTable (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_words_list_created_at
      ON $wordsTable (list_id, created_at DESC)
    ''');
  }

  Future<void> ensureTranslationCacheTable([Database? existingDb]) async {
    final db = existingDb ?? await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $translationCacheTable (
        cache_key TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        context_sentence TEXT NOT NULL,
        translation TEXT NOT NULL,
        part_of_speech TEXT,
        meanings_json TEXT,
        source TEXT NOT NULL DEFAULT 'contextual_free',
        updated_at INTEGER NOT NULL
      )
    ''');

    final columns = await db.rawQuery('PRAGMA table_info($translationCacheTable)');
    final hasMeaningsJson = columns.any((col) => col['name'] == 'meanings_json');
    if (!hasMeaningsJson) {
      await db.execute(
        'ALTER TABLE $translationCacheTable ADD COLUMN meanings_json TEXT',
      );
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_translation_cache_updated_at
      ON $translationCacheTable (updated_at DESC)
    ''');
  }

  Future<void> ensureSettingsTable([Database? existingDb]) async {
    final db = existingDb ?? await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $settingsTable (
        "key" TEXT PRIMARY KEY,
        "value" TEXT
      )
    ''');
  }

  Future<void> ensureFavoriteSitesTable([Database? existingDb]) async {
    final db = existingDb ?? await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $favoriteSitesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_favorite_sites_created_at
      ON $favoriteSitesTable (created_at DESC)
    ''');
  }

  Future<void> ensureArticlesCacheTable([Database? existingDb]) async {
    final db = existingDb ?? await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $articlesCacheTable (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        summary TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        level TEXT NOT NULL DEFAULT '',
        language TEXT NOT NULL DEFAULT 'en',
        author TEXT NOT NULL DEFAULT '',
        image_url TEXT,
        source_url TEXT,
        reading_time_minutes INTEGER NOT NULL DEFAULT 0,
        tags_json TEXT NOT NULL DEFAULT '[]',
        published_at INTEGER,
        updated_at INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL DEFAULT '{}',
        cached_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_articles_cache_sort_order
      ON $articlesCacheTable (sort_order ASC, published_at DESC)
    ''');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
      _ensuredSchemaVersion = 0;
    }
  }
}
