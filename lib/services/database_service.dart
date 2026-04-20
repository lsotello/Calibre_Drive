import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../models/book_model.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseService {
  // 1. Cria a instância interna privada
  static final DatabaseService _instance = DatabaseService._internal();

  // 2. Construtor fábrica que sempre retorna a mesma instância
  factory DatabaseService() {
    return _instance;
  }

  // 3. Construtor nomeado privado
  DatabaseService._internal();

  Database? _booksDb; // O metadata.db (Somente Leitura)
  Database? _cacheDb; // O app_cache.db (Nosso banco interno)

  Future<void> initDatabases() async {
    if (_cacheDb != null) return;
    final docsDir = await getApplicationDocumentsDirectory();
    String cachePath = join(docsDir.path, 'app_cache.db');

    _cacheDb = await openDatabase(
      cachePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS drive_cache (
            folder_path TEXT PRIMARY KEY, 
            cover_file_id TEXT
          )
        ''');
      },
    );
  }

  // Função para salvar o ID da capa sem tocar no banco do Calibre
  Future<void> saveCoverId(String folderId, String fileId) async {
    await _cacheDb?.insert('drive_cache', {
      'folder_id': folderId,
      'cover_file_id': fileId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Função para buscar o ID da capa no nosso banco auxiliar
  Future<String?> getCoverId(String folderId) async {
    final res = await _cacheDb?.query(
      'drive_cache',
      columns: ['cover_file_id'],
      where: 'folder_id = ?',
      whereArgs: [folderId],
    );
    return res?.isNotEmpty == true
        ? res!.first['cover_file_id'] as String
        : null;
  }

  // Função principal de busca com filtros dinâmicos
  Future<List<BookModel>> searchBooks({
    String query = '',
    String? seriesFilter,
    String? authorFilter,
    String? formatFilter,
  }) async {
    if (_cacheDb == null) {
      //await initDatabases();

      final test = await _cacheDb!.rawQuery(
        'SELECT COUNT(*) as total FROM drive_cache',
      );
      print("Quantidade de capas no cache: ${test.first['total']}");
    }

    if (_booksDb == null) {
      print("Banco do Calibre ainda não disponível.");
      return [];
    }

    // 1. Base da Query com os Joins necessários
    String sql = '''
      SELECT 
        b.id, b.title, b.path, b.series_index,
        a.name AS author_name,
        s.name AS series_name
      FROM books b
      LEFT JOIN books_authors_link bal ON b.id = bal.book
      LEFT JOIN authors a ON bal.author = a.id
      LEFT JOIN books_series_link bsl ON b.id = bsl.book
      LEFT JOIN series s ON bsl.series = s.id
    ''';

    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    // 2. Filtro de Texto (Busca em Título, Autor ou Série)
    if (query.isNotEmpty) {
      whereClauses.add('(b.title LIKE ? OR a.name LIKE ? OR s.name LIKE ?)');
      whereArgs.addAll(['%$query%', '%$query%', '%$query%']);
    }

    // 3. Filtros Específicos (Exemplo: Clicou em uma Série específica)
    if (seriesFilter != null) {
      whereClauses.add('s.name = ?');
      whereArgs.add(seriesFilter);
    }

    // 4. Montagem Final
    if (whereClauses.isNotEmpty) {
      sql += ' WHERE ${whereClauses.join(' AND ')}';
    }

    // Ordenação (Padrão por título, mas fácil de mudar)
    sql += ' ORDER BY b.title COLLATE NOCASE ASC';

    final List<Map<String, dynamic>> results = await _booksDb!.rawQuery(
      sql,
      whereArgs,
    );

    // 2. Busca TODO o seu cache local de capas (do app_cache.db)
    // Assumindo que _cacheDb é o seu banco local
    final List<Map<String, dynamic>> cacheMaps = await _cacheDb!.query(
      'drive_cache',
    );

    // Criamos um mapa rápido para busca: { "caminho/no/calibre": "fileIdDoGoogle" }
    Map<String, String> coverMap = {
      for (var item in cacheMaps)
        item['folder_path'].toString().trim(): item['cover_file_id'].toString(),
    };

    // 3. Unimos os dois no Dart
    int index = 0;

    return results.map((map) {
      final bookPath = map['path'].toString().trim();
      final coverId = coverMap[bookPath];

      // ADICIONE ESTES PRINTS:
      if (index < 5) {
        // Printa apenas os 5 primeiros para não inundar o console
        print("--- COMPARANDO ---");
        print("DB Path:  '$bookPath'");
        print("Cache Keys Disponíveis: ${coverMap.keys.take(5).toList()}");
        print("------------------");
        index = index + 1;
      }

      // LOG PARA DEBUG:
      //print("Tentando casar livro: ${map['title']}");
      //print("Path do livro no DB: $bookPath");
      print("ID da capa encontrado no cache: $coverId");

      // 1. Aqui você poderia buscar os formatos reais se quisesse,
      // mas por enquanto passamos uma lista vazia [] para não dar erro.
      List<String> formats = [];

      return BookModel.fromMap(
        map, // 1º argumento posicional
        formats, // 2º argumento posicional
        coverId: coverMap[map['path']], // Argumento nomeado (dentro das {})
      );
    }).toList();
  }

  // Modificado para aceitar o map completo e usar transaction (mais rápido)
  Future<void> saveCoverCache(Map<String, String> coverMap) async {
    if (_cacheDb == null) await initDatabases();
    await _cacheDb!.transaction((txn) async {
      for (var entry in coverMap.entries) {
        await txn.insert('drive_cache', {
          'folder_path': entry.key,
          'cover_file_id': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> openCalibreDatabase(String path) async {
    // Abrimos como readOnly: true para total segurança. Nunca alteraremos o banco original.
    _booksDb = await openDatabase(path, readOnly: true);
    print("Banco do Calibre aberto em: $path");
  }

  // Adicione estes métodos ao seu DatabaseService

  // Abre o metadata.db que já foi baixado anteriormente
  Future<bool> openExistingDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    String path = join(docsDir.path, 'metadata.db');
    if (await File(path).exists()) {
      _booksDb = await openDatabase(path, readOnly: true);
      return true;
    }
    return false;
  }

  // Retorna a data de modificação do arquivo local para comparar com o Drive
  Future<DateTime?> getLocalMetadataDate() async {
    final docsDir = await getApplicationDocumentsDirectory();
    File file = File(join(docsDir.path, 'metadata.db'));
    if (await file.exists()) {
      return await file.lastModified();
    }
    return null;
  }

  // Busca um ID de capa específico no cache
  Future<String?> getCachedCoverId(String folderPath) async {
    final res = await _cacheDb?.query(
      'drive_cache',
      where: 'folder_path = ?',
      whereArgs: [folderPath],
    );
    return res?.isNotEmpty == true
        ? res!.first['cover_file_id'] as String
        : null;
  }
}
