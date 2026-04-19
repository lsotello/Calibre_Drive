import 'package:sqflite/sqflite.dart';
import '../models/book_model.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseService {
  Database? _booksDb; // O metadata.db (Somente Leitura)
  Database? _cacheDb; // O app_cache.db (Nosso banco interno)

  Future<void> initDatabases() async {
    final docsDir = await getApplicationDocumentsDirectory();

    // 1. Inicializa o banco de CACHE interno
    String cachePath = join(docsDir.path, 'app_cache.db');
    _cacheDb = await openDatabase(
      cachePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS drive_cache (
            folder_id TEXT PRIMARY KEY,
            cover_file_id TEXT
          )
        ''');
      },
    );

    // 2. O metadata.db será aberto dinamicamente após o download
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
    if (_booksDb == null) return [];

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

    // 5. Mapeamento para o nosso Model
    return results.map((map) => BookModel.fromMap(map, [])).toList();
  }

  Future<void> saveCoverCache(Map<String, String> coverMap) async {
    if (_cacheDb == null) return;

    // Usamos um batch para alta performance em inserções múltiplas
    final batch = _cacheDb!.batch();

    coverMap.forEach((folderId, coverFileId) {
      batch.insert('drive_cache', {
        'folder_id': folderId,
        'cover_file_id': coverFileId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    await batch.commit(noResult: true);
    print("Cache de capas atualizado: ${coverMap.length} itens.");
  }

  Future<void> openCalibreDatabase(String path) async {
    // Abrimos como readOnly: true para total segurança. Nunca alteraremos o banco original.
    _booksDb = await openDatabase(path, readOnly: true);
    print("Banco do Calibre aberto em: $path");
  }
}
