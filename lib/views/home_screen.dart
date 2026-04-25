import 'dart:io';
import 'package:calibre_drive/views/category_view.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../services/database_service.dart';
import '../services/google_drive_service.dart';
import '../services/settings_service.dart';
import '../views/books_view.dart';
import 'custom_drawer.dart';
import '../utils/logger.dart'; // O importante!

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GoogleDriveService _googleDriveService = GoogleDriveService();
  final DatabaseService _dbService = DatabaseService();

  bool _isLoading = true;
  Map<String, String> _authHeaders = {};
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    logger.i("Iniciando aplicativo...");
    await _dbService.initDatabases();

    bool hasLocalData = await _dbService.openExistingDatabase();
    if (hasLocalData) {
      logger.d("Banco local encontrado e aberto.");
    } else {
      logger.w("Nenhum banco local metadata.db encontrado.");
    }

    setState(() => _isLoading = false);
    _syncLibrary();
  }

  Future<void> _syncLibrary() async {
    logger.i("Iniciando verificação de sincronia com Google Drive...");
    setState(() => _isLoading = true);

    try {
      if (!await _googleDriveService.signIn()) {
        logger.w("Usuário não realizou login no Google Drive.");
        return;
      }

      _authHeaders = await _googleDriveService.getAuthHeaders();

      final String? folderId = await _googleDriveService.findCalibreFolderId(
        "Biblioteca do Calibre",
      );

      if (folderId == null) {
        logger.e("Pasta 'Biblioteca do Calibre' não encontrada no Drive.");
        return;
      }

      final String? dbFileId = await _googleDriveService.findFileIdByName(
        "metadata.db",
        folderId,
      );

      if (dbFileId != null) {
        await SettingsService.setDbFileId(dbFileId);
        final remoteMeta = await _googleDriveService.getFileMetadata(dbFileId);

        String? lastSyncLocalStr = await SettingsService.getLastSync();
        final dbDir = await getDatabasesPath();
        final localFile = File("$dbDir/metadata.db");

        bool needsUpdate = true;
        if (remoteMeta?.modifiedTime != null &&
            await localFile.exists() &&
            lastSyncLocalStr != null) {
          int remoteMs = remoteMeta!.modifiedTime!
              .toUtc()
              .millisecondsSinceEpoch;
          int localMs = DateTime.parse(
            lastSyncLocalStr,
          ).toUtc().millisecondsSinceEpoch;

          if (remoteMs <= localMs) {
            needsUpdate = false;
            logger.i(
              "Biblioteca já está atualizada (Remoto: $remoteMs | Local: $localMs)",
            );
          }
        }

        if (needsUpdate) {
          logger.d(
            "Nova versão detectada no Drive. Solicitando confirmação...",
          );
          bool? confirm = await _showUpdateDialog();
          if (confirm == true) {
            logger.i("Iniciando download do metadata.db...");
            final file = await _googleDriveService.downloadMetadata(dbFileId);
            if (file != null) {
              await _dbService.openCalibreDatabase(file.path);
              logger.i("Processando biblioteca (Scan de capas e arquivos)...");
              await _googleDriveService.scanEverything(folderId, _dbService);

              if (remoteMeta?.modifiedTime != null) {
                await SettingsService.setLastSync(
                  remoteMeta!.modifiedTime!.toUtc().toIso8601String(),
                );
              }
              logger.i("Sincronização finalizada com sucesso! ✅");
            }
          }
        }
      }
    } catch (e, stack) {
      logger.e("Erro crítico na sincronização", error: e, stackTrace: stack);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ... (build, _showUpdateDialog e outros métodos permanecem os mesmos) ...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? "Meus Livros"
              : _currentIndex == 1
              ? "Séries"
              : "Autores",
        ),
      ),
      drawer: CustomDrawer(
        authHeaders: _authHeaders,
        onSyncComplete: () {
          logger.d("Sync via Drawer finalizado. Recarregando interface...");
          setState(() {});
        },
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          BooksView(
            authHeaders: _authHeaders,
            dbService: _dbService,
            isLoading: _isLoading,
          ),
          CategoryView(
            title: "Séries",
            future: _dbService.getSeries(),
            onTap: (name) =>
                _navigateToFilteredBooks("Série: $name", {"series": name}),
          ), // Aba 1
          CategoryView(
            title: "Autores",
            future: _dbService.getAuthors(),
            onTap: (name) =>
                _navigateToFilteredBooks("Autor: $name", {"author": name}),
          ), // Aba 2
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          logger.t("Mudando para aba índice: $index");
          setState(() => _currentIndex = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Livros'),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books),
            label: 'Séries',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Autores'),
        ],
      ),
    );
  }

  Future<bool?> _showUpdateDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sincronização"),
        content: const Text(
          "Existem novos livros ou alterações no seu Drive. Deseja atualizar agora?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("PULAR"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("ATUALIZAR"),
          ),
        ],
      ),
    );
  }

  void _navigateToFilteredBooks(String title, Map<String, String> filters) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(title)),
          // Reutilizamos a BooksView, mas passamos os filtros
          body: BooksView(
            authHeaders: _authHeaders,
            dbService: _dbService,
            isLoading: _isLoading,
            initialFilters: filters,
          ),
        ),
      ),
    );
  }
}
