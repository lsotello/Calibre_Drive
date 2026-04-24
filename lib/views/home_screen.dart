import 'dart:io';
import 'package:calibre_drive/services/settings_service.dart';
import 'package:calibre_drive/utils/logger.dart';
import 'package:calibre_drive/views/books_view.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../services/database_service.dart';
import '../services/google_drive_service.dart';
import 'custom_drawer.dart';

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
    await _dbService.initDatabases();
    // Primeiro, tenta abrir o que já existe para mostrar algo ao usuário
    await _dbService.openExistingDatabase();

    // Notifica que o banco inicial está pronto para as abas
    setState(() => _isLoading = false);

    // Depois, faz a verificação de sincronização em segundo plano
    _syncLibrary();
  }

  Future<void> _syncLibrary() async {
    setState(() => _isLoading = true);
    try {
      await _dbService.initDatabases();
      if (!await _googleDriveService.signIn()) return;

      _authHeaders = await _googleDriveService.getAuthHeaders();
      final String? folderId = await _googleDriveService.findCalibreFolderId(
        "Biblioteca do Calibre",
      );
      if (folderId == null) return;

      // Busca ID do metadata.db no Drive
      final String? dbFileId = await _googleDriveService.findFileIdByName(
        "metadata.db",
        folderId,
      );

      if (dbFileId != null) {
        await SettingsService.setDbFileId(dbFileId); // Salva para uso futuro

        final remoteMeta = await _googleDriveService.getFileMetadata(dbFileId);

        bool needsUpdate = true;

        // 1. Pegar a data salva no SharedPreferences
        String? lastSyncLocalStr = await SettingsService.getLastSync();

        // 2. Localizar o arquivo onde o banco REALMENTE é aberto
        final dbDir = await getDatabasesPath();
        final localFile = File("$dbDir/metadata.db");

        bool fileExists = await localFile.exists();

        if (remoteMeta != null && remoteMeta.modifiedTime != null) {
          // Pegamos o timestamp da nuvem em milissegundos
          int remoteMs = remoteMeta.modifiedTime!
              .toUtc()
              .millisecondsSinceEpoch;

          if (fileExists && lastSyncLocalStr != null) {
            // Pegamos o timestamp local salvo
            int localMs = DateTime.parse(
              lastSyncLocalStr,
            ).toUtc().millisecondsSinceEpoch;

            // Se o remoto for menor ou igual ao local, não precisa de update
            if (remoteMs <= localMs) {
              needsUpdate = false;
            }

            logger.d(
              "Remoto: $remoteMs | Local: $localMs | Update: $needsUpdate",
            );
          }
        }
        // ---------------------------------------------------

        logger.d("Needs Update: $needsUpdate");

        if (needsUpdate) {
          bool? confirm = await _showUpdateDialog();
          if (confirm == true) {
            final file = await _googleDriveService.downloadMetadata(dbFileId);
            if (file != null) {
              await _dbService.openCalibreDatabase(file.path);

              // Importante: scanEverything deve ocorrer antes de finalizar a carga
              await _googleDriveService.scanEverything(folderId, _dbService);

              // SALVA A DATA DA NUVEM COMO DATA LOCAL (O "CARIMBO")
              if (remoteMeta?.modifiedTime != null) {
                await SettingsService.setLastSync(
                  remoteMeta!.modifiedTime!.toUtc().toIso8601String(),
                );
              }

              setState(() => _isLoading = false);
            }
          } else {
            logger.d("1-Abrindo banco local existente...");
            await _dbService.openExistingDatabase();
          }
        } else {
          logger.d("Já atualizado. Abrindo banco local...");

          // Pegamos o caminho padrão onde o banco é salvo no Android
          final dbDir = await getDatabasesPath();
          final localPath = "$dbDir/metadata.db";

          // Verificamos se o arquivo realmente existe antes de tentar abrir
          if (await File(localPath).exists()) {
            await _dbService.openCalibreDatabase(localPath);
          } else {
            logger.e("O arquivo deveria estar aqui, mas sumiu: $localPath");
            // Caso o arquivo suma, talvez valha forçar o needsUpdate = true;
          }
        }
      }

      // Garante que o carregamento pare antes de tentar pesquisar
      setState(() => _isLoading = false);

      // Agora que o banco está aberto (via download ou via local), a busca vai funcionar
    } catch (e) {
      logger.e("Erro: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      BooksView(
        authHeaders: _authHeaders,
        dbService: _dbService,
        isLoading: _isLoading,
      ),
      const Center(child: Text("Séries em breve")),
      const Center(child: Text("Autores em breve")),
    ];

    return Scaffold(
      drawer: CustomDrawer(
        authHeaders: _authHeaders,
        onSyncComplete: () {
          setState(() {});
        },
      ),
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
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
}
