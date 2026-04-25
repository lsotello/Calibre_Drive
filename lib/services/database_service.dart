import 'dart:io';
import 'package:calibre_drive/utils/logger.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book_model.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseService {
  // 1. Cria a instância interna privada
  static final DatabaseService _instance = DatabaseService._internal();
  bool _isAttaching = false; // Trava de segurança

  // 2. Construtor fábrica que sempre retorna a mesma instância
  factory DatabaseService() {
    return _instance;
  }

  // 3. Construtor nomeado privado
  DatabaseService._internal();

  Database? _booksDb; // O metadata.db (Somente Leitura)
  Database? _cacheDb; // O app_cache.db (Nosso banco interno)

  // Função simples para checar se o banco está pronto
  bool isCalibreReady() => _booksDb != null;
  bool isCacheReady() => _cacheDb != null;

  Future<void> initDatabases() async {
    if (_cacheDb != null) return;

    final docsDir = await getApplicationDocumentsDirectory();
    String cachePath = join(docsDir.path, 'app_cache.db');

    _cacheDb = await openDatabase(
      cachePath,
      version: 1,
      onCreate: (db, version) async {
        logger.i("Criando banco de cache pela primeira vez...");

        // Tabela de Capas
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cover_cache (
            book_id INTEGER PRIMARY KEY, 
            google_drive_id TEXT
          )
        ''');

        // Tabela de Arquivos (Epub/PDF)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS file_cache (
            book_id INTEGER,
            format TEXT,
            file_id TEXT,
            PRIMARY KEY (book_id, format)
          )
        ''');

        // --- NOVA TABELA: Status de Leitura ---
        await db.execute('''
        CREATE TABLE reading_status (
          book_id INTEGER PRIMARY KEY,
          status TEXT DEFAULT 'pending', -- 'pending', 'reading', 'finished'
          progress REAL DEFAULT 0.0,
          last_access TEXT
        )
      ''');

        logger.i("Tabela reading_status criada com sucesso.");
      },
    );
  }

  // Função para salvar o ID da capa sem tocar no banco do Calibre
  Future<void> saveCoverId(String folderId, String fileId) async {
    await _cacheDb?.insert('cover_cache', {
      'book_id': folderId,
      'google_drive_id': fileId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Função para buscar o ID da capa no nosso banco auxiliar
  Future<String?> getCoverId(String bookId) async {
    if (_cacheDb == null) return null;

    final res = await _cacheDb?.query(
      'cover_cache',
      columns: ['google_drive_id'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );

    return res?.isNotEmpty == true
        ? res!.first['google_drive_id'] as String
        : null;
  }

  // Função principal de busca com filtros dinâmicos
  Future<List<BookModel>> searchBooks({
    String query = '',
    String? seriesFilter,
    String? authorFilter,
    String? formatFilter,
  }) async {
    // 1. Teste do Banco de Cache (onde está o reading_status)
    if (_cacheDb == null || !_cacheDb!.isOpen) {
      logger.w(
        "searchBooks: Banco de Cache não disponível. Tentando religar...",
      );
      await initDatabases();
    }

    // 2. Teste do Banco do Calibre (onde estão os livros)
    // Se o banco do Calibre não estiver aberto, tenta abrir AGORA
    if (_booksDb == null || !_booksDb!.isOpen) {
      bool opened = await openExistingDatabase();
      if (!opened) {
        logger.e("Não foi possível abrir o Banco do Calibre para a busca.");
        return [];
      }
    }

    // 3. Verificação Final: Se algum falhou, não rodamos a query para evitar crash
    if (_booksDb == null || _cacheDb == null) {
      logger.e(
        "searchBooks: Abortando busca. Um ou ambos os bancos estão inacessíveis.",
      );
      return [];
    }

    try {
      // 1. Base da Query com os Joins necessários
      String sql = '''
      SELECT 
        b.id, b.title, b.path, b.series_index,
        GROUP_CONCAT(a.name, ' & ') as author_name,
        s.name AS series_name,
        rs.status as reading_status
      FROM books b
      LEFT JOIN books_authors_link bal ON b.id = bal.book
      LEFT JOIN authors a ON bal.author = a.id
      LEFT JOIN books_series_link bsl ON b.id = bsl.book
      LEFT JOIN series s ON bsl.series = s.id
      LEFT JOIN cache.reading_status rs ON b.id = rs.book_id
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

      // Agrupa para não repetir livros com mais de um autor
      sql += ' GROUP BY b.id ';

      // Ordenação (Padrão por título, mas fácil de mudar)
      //sql += ' ORDER BY b.title COLLATE NOCASE ASC';

      if (seriesFilter != null) {
        // Ordenamos pelo series_index para que os livros fiquem na ordem da história
        sql += " ORDER BY b.series_index ASC, b.title ASC";
      } else {
        sql += " ORDER BY b.title COLLATE NOCASE ASC";
      }

      final List<Map<String, dynamic>> results = await _booksDb!.rawQuery(
        sql,
        whereArgs,
      );

      // 2. Busca TODO o seu cache local de capas (do app_cache.db)
      // Assumindo que _cacheDb é o seu banco local
      final List<Map<String, dynamic>> cacheMaps = await _cacheDb!.query(
        'cover_cache',
      );

      // Criamos um mapa rápido para busca: { "caminho/no/calibre": "fileIdDoGoogle" }
      Map<int, String> coverMap = {
        for (var item in cacheMaps)
          item['book_id'] as int: item['google_drive_id'].toString(),
      };

      // 3. Unimos os dois no Dart
      return results.map((map) {
        // 1. Aqui você poderia buscar os formatos reais se quisesse,
        // mas por enquanto passamos uma lista vazia [] para não dar erro.
        List<String> formats = [];

        return BookModel.fromMap(
          map, // 1º argumento posicional
          formats, // 2º argumento posicional
          coverId:
              coverMap[map['id']], // BUSCA PELO ID (map['id']), NÃO PELO PATH
        );
      }).toList();
    } catch (e, stack) {
      logger.e("Erro ao executar query de busca", error: e, stackTrace: stack);
      return [];
    }
  }

  // Modificado para aceitar o map completo e usar transaction (mais rápido)
  Future<void> saveCoverCache(List<Map<String, String>> covers) async {
    if (_cacheDb == null) return;

    final batch = _cacheDb!.batch();
    for (var cover in covers) {
      batch.insert('cover_cache', {
        'book_id': int.parse(cover['id']!), // Converte o ID para int
        'google_drive_id': cover['fileId']!,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> openCalibreDatabase(String path) async {
    // Abrimos como readOnly: true para total segurança. Nunca alteraremos o banco original.
    _booksDb = await openDatabase(path, readOnly: true);
    logger.i("Banco do Calibre aberto em: $path");
  }

  // Adicione estes métodos ao seu DatabaseService

  // Abre o metadata.db que já foi baixado anteriormente
  Future<bool> openExistingDatabase() async {
    if (_isAttaching) return true;

    try {
      final dbDir = await getDatabasesPath();
      final dbPath = join(dbDir, 'metadata.db');
      final cachePath = join(
        (await getApplicationDocumentsDirectory()).path,
        'app_cache.db',
      );

      if (await File(dbPath).exists()) {
        // Abre o banco se estiver nulo ou fechado
        if (_booksDb == null || !_booksDb!.isOpen) {
          _booksDb = await openDatabase(dbPath, readOnly: false);
        }

        // VERIFICAÇÃO: O banco 'cache' já está anexado?
        List<Map> databases = await _booksDb!.rawQuery("PRAGMA database_list");
        bool isAttached = databases.any((db) => db['name'] == 'cache');

        if (!isAttached) {
          await _booksDb!.execute("ATTACH DATABASE '$cachePath' AS cache");
          logger.i("Banco de cache anexado com sucesso.");
        }

        return true;
      }
      return false;
    } catch (e) {
      // Se o erro for "already in use", não tratamos como erro fatal
      if (e.toString().contains("already in use")) {
        return true;
      }
      logger.e("Erro ao conectar bancos", error: e);
      return false;
    } finally {
      _isAttaching = false; // Libera a trava independente de sucesso ou erro
    }
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
      'cover_cache',
      where: 'book_id = ?',
      whereArgs: [folderPath],
    );
    return res?.isNotEmpty == true
        ? res!.first['cover_file_id'] as String
        : null;
  }

  Future<String?> getBookComment(int bookId) async {
    if (_booksDb == null) return null;

    final List<Map<String, dynamic>> res = await _booksDb!.query(
      'comments',
      columns: ['text'],
      where: 'book = ?',
      whereArgs: [bookId],
    );

    if (res.isNotEmpty) {
      // O Calibre às vezes salva em HTML, podemos precisar limpar depois
      return res.first['text'] as String;
    }
    return null;
  }

  // No seu DatabaseService
  Future<void> saveFileCache(List<Map<String, dynamic>> files) async {
    if (_cacheDb == null) return;

    final batch = _cacheDb!.batch();
    for (var file in files) {
      batch.insert('file_cache', {
        'book_id': file['book_id'],
        'format': file['format'],
        'file_id': file['file_id'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<String?> getFileId(int bookId, String format) async {
    final res = await _cacheDb!.query(
      'file_cache',
      where: 'book_id = ? AND format = ?',
      whereArgs: [bookId, format.toLowerCase()],
    );
    if (res.isNotEmpty) return res.first['file_id'] as String;
    return null;
  }

  Future<void> closeDatabase() async {
    final db = _booksDb; // Sua variável interna do banco
    if (db != null) {
      await db.close();
      _booksDb = null;
    }
  }

  Future<String> getDatabasePath() async {
    final directory = await getApplicationDocumentsDirectory();
    // O banco fica escondido do usuário, protegido pelo sistema
    return "${directory.path}/metadata.db";
  }

  // Função para forçar a espera da inicialização se necessário
  Future<void> ensureInitialized() async {
    if (_cacheDb == null) {
      await initDatabases();
    }
  }

  Future<void> updateReadingStatus(int bookId, String status) async {
    if (_cacheDb == null) return;

    try {
      await _cacheDb!.insert('reading_status', {
        'book_id': bookId,
        'status': status,
        'last_access': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      logger.i("Status do livro $bookId atualizado para: $status");
    } catch (e) {
      logger.e("Erro ao atualizar status de leitura", error: e);
    }
  }

  // Busca todas as séries e quantos livros cada uma tem
  Future<List<Map<String, dynamic>>> getSeries() async {
    await openExistingDatabase();

    if (_booksDb == null) {
      logger.e("Tentativa de buscar séries com banco nulo.");
      return [];
    }

    return await _booksDb!.rawQuery('''
    SELECT 
      s.name as name, 
      COUNT(bsl.book) as count 
    FROM series s
    JOIN books_series_link bsl ON s.id = bsl.series
    JOIN books b ON bsl.book = b.id
    GROUP BY s.id
    ORDER BY s.name ASC
    ''');
  }

  // Busca todos os autores e contagem
  Future<List<Map<String, dynamic>>> getAuthors() async {
    await openExistingDatabase();

    if (_booksDb == null) {
      logger.e("Tentativa de buscar séries com banco nulo.");
      return [];
    }

    return await _booksDb!.rawQuery('''
    SELECT 
      a.name as name, 
      COUNT(bal.book) as count 
    FROM authors a
    JOIN books_authors_link bal ON a.id = bal.author
    GROUP BY a.id
    ORDER BY a.name ASC
    ''');
  }
}
