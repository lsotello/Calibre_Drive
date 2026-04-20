import 'dart:io';

import 'package:calibre_drive/widgets/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/book_model.dart';
import '../services/database_service.dart';
import '../services/google_drive_service.dart';

// Definimos os modos de visualização
enum ViewMode { grid, listWithCover, compactList }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 1. Instancie o serviço aqui:
  final GoogleDriveService _googleDriveService = GoogleDriveService();
  final DatabaseService _dbService = DatabaseService();

  // 1. Estado da Tela
  ViewMode _currentViewMode = ViewMode.grid;
  String _searchQuery = "";
  List<BookModel> _books = [];
  bool _isLoading = true;

  Map<String, String> _authHeaders = {};

  @override
  void initState() {
    super.initState();
    // Inicializa o banco de cache antes de tudo
    _dbService.initDatabases().then((_) => _syncLibrary());
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
        final remoteMeta = await _googleDriveService.getFileMetadata(dbFileId);
        final localFile = File(
          "${(await getApplicationDocumentsDirectory()).path}/metadata.db",
        );

        bool needsUpdate = true;
        if (remoteMeta != null) {
          // <--- Verificação de segurança para o objeto
          if (await localFile.exists()) {
            DateTime localDate = await localFile.lastModified();

            // Usamos ?. para acessar a data e ?? para o padrão caso seja nulo
            DateTime remoteDate =
                remoteMeta.modifiedTime ??
                DateTime.fromMillisecondsSinceEpoch(0);

            // Se o remoto NÃO for mais novo que o local (com margem de 1s), não precisa baixar
            if (!remoteDate.isAfter(
              localDate.add(const Duration(seconds: 1)),
            )) {
              needsUpdate = false;
            }
          }
        } else {
          // Se não conseguirmos pegar o metadado remoto, por segurança,
          // tentamos usar o local se ele existir.
          needsUpdate = !await localFile.exists();
        }

        if (needsUpdate) {
          bool? confirm = await _showUpdateDialog();
          if (confirm == true) {
            final file = await _googleDriveService.downloadMetadata(dbFileId);
            if (file != null) {
              await _dbService.openCalibreDatabase(file.path);
              // Atualiza capas apenas se o usuário baixar o banco novo
              final covers = await _googleDriveService.scanFolderForCovers(
                folderId,
              );
              await _dbService.saveCoverCache(covers);
            }
          } else {
            await _dbService.openExistingDatabase();
          }
        } else {
          await _dbService.openExistingDatabase();
        }
      }

      _performSearch();
    } catch (e) {
      print("Erro: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Função auxiliar para comparar datas
  Future<bool> _checkIfNeedsUpdate(dynamic remoteMetadata) async {
    // Aqui você deve implementar a lógica de comparar a data do arquivo local
    // com remoteMetadata.modifiedTime. Se não houver arquivo local, retorna true.
    return true; // Simulação: sempre assume que precisa até você implementar o File.exists()
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

  Future<void> _performSearch() async {
    // Busca os livros no banco que já foi aberto no celular
    final books = await _dbService.searchBooks(query: _searchQuery);
    setState(() {
      _books = books;
    });
  }

  // 2. Construção da Interface Principal
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // Alinha à esquerda
          children: [
            const Text('Calibre Drive'),
            Text(
              '${_books.length} livros encontrados',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Color.fromARGB(
                  179,
                  4,
                  9,
                  88,
                ), // Cor levemente transparente
              ),
            ),
          ],
        ),
        bottom: _buildSearchAndFilterBar(), // Barra de busca dinâmica
        actions: [
          _buildViewModeSelector(), // Botão de alternar Grid/Lista
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBookDisplay(), // Decide qual layout mostrar
    );
  }

  // 3. Componentes da UI (Funções Auxiliares)

  PreferredSizeWidget _buildSearchAndFilterBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          onChanged: (value) {
            setState(() => _searchQuery = value);
            _performSearch(); // Vamos criar essa função agora
          },
          decoration: InputDecoration(
            hintText: 'Buscar por título, autor ou série...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _showFilterSheet(), // Abre filtros avançados
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Widget _buildViewModeSelector() {
    return PopupMenuButton<ViewMode>(
      icon: const Icon(Icons.grid_view),
      onSelected: (ViewMode mode) => setState(() => _currentViewMode = mode),
      itemBuilder: (context) => [
        _buildPopupItem(ViewMode.grid, Icons.grid_on, 'Grade'),
        _buildPopupItem(
          ViewMode.listWithCover,
          Icons.format_list_bulleted,
          'Lista com Capa',
        ),
        _buildPopupItem(ViewMode.compactList, Icons.reorder, 'Lista Compacta'),
      ],
    );
  }

  // Função auxiliar para criar os itens com marcação de selecionado
  PopupMenuItem<ViewMode> _buildPopupItem(
    ViewMode mode,
    IconData icon,
    String label,
  ) {
    final bool isSelected = _currentViewMode == mode;

    return PopupMenuItem<ViewMode>(
      value: mode,
      child: Row(
        children: [
          Icon(icon, color: isSelected ? Colors.blue : Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isSelected) const Icon(Icons.check, color: Colors.blue, size: 20),
        ],
      ),
    );
  }

  Widget _buildBookDisplay() {
    if (_currentViewMode == ViewMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65, // Ajustado para caber o título embaixo
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _books.length,
        itemBuilder: (context, index) => _buildGridItem(_books[index]),
      );
    } else {
      // Para Listas (Com capa ou Compacta)
      return ListView.separated(
        itemCount: _books.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) => _buildListItem(_books[index]),
      );
    }
  }

  // Funções de clique e filtros (Lógica de navegação)
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: const Text('Filtros por Autor, Série e Formato virão aqui!'),
      ),
    );
  }

  // Stubs para os itens (serão widgets separados depois)
  Widget _buildGridItem(BookModel book) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A CAPA DO LIVRO
          Expanded(
            child: AspectRatio(
              aspectRatio: 2 / 3, // Proporção padrão de capas de livros
              child: BookCover(
                fileId: book.coverId, // Este ID vem do seu banco de cache
                authHeaders: _authHeaders,
              ),
            ),
          ),
          // O TÍTULO
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(BookModel book) {
    // Define o modo atual
    bool isListWithCover = _currentViewMode == ViewMode.listWithCover;

    return ListTile(
      // Reduz o espaço interno se for lista compacta
      dense: !isListWithCover,

      // Ajusta o padding vertical conforme o modo
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isListWithCover ? 8 : 0,
      ),

      // Lado Esquerdo
      leading: isListWithCover
          ? SizedBox(
              width: 45,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: BookCover(
                    fileId: book.coverId,
                    authHeaders: _authHeaders,
                  ),
                ),
              ),
            )
          : const Icon(Icons.book, size: 20), // Ícone menor na lista compacta
      // Centro
      title: Text(
        book.title,
        maxLines: 1, // Na compacta, apenas 1 linha para economizar espaço
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isListWithCover ? FontWeight.bold : FontWeight.normal,
          fontSize: isListWithCover ? 16 : 14,
        ),
      ),

      subtitle: Text(
        book.author,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),

      // Lado Direito (opcional: remover na compacta para limpar o visual)
      trailing: isListWithCover
          ? const Icon(Icons.chevron_right, size: 18)
          : null,

      onTap: () {
        // Ação de clique
      },
    );
  }
}
