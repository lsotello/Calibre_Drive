import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _syncLibrary();
  }

  Future<void> _syncLibrary() async {
    setState(() => _isLoading = true);

    try {
      // 1. LOGIN: Entra na conta do Google
      bool success = await _googleDriveService.signIn();
      if (!success) {
        print("Erro: Não foi possível fazer login.");
        return;
      }

      // 2. LOCALIZAÇÃO: Busca o ID da pasta "Biblioteca do Calibre"
      // Aqui nós pegamos o ID que faltava (o rootId)
      final String? folderId = await _googleDriveService.findCalibreFolderId(
        "Biblioteca do Calibre",
      );

      if (folderId == null) {
        print("Erro: Pasta não encontrada no Drive.");
        return;
      }

      // 3. BANCO DE DADOS: Localiza e baixa o metadata.db
      final String? dbFileId = await _googleDriveService.findFileIdByName(
        "metadata.db",
        folderId,
      );
      if (dbFileId != null) {
        final file = await _googleDriveService.downloadMetadata(dbFileId);
        if (file != null) {
          // Abre o banco para podermos ler os livros
          await _dbService.openCalibreDatabase(file.path);
        }
      }

      // 4. CAPAS: Faz a varredura usando o ID da pasta que encontramos no passo 2
      final coverIds = await _googleDriveService.scanFolderForCovers(folderId);

      // 5. CACHE: Salva os IDs das capas no nosso banco auxiliar
      await _dbService.saveCoverCache(coverIds);

      // 6. UI: Atualiza a lista de livros na tela
      final books = await _dbService.searchBooks(query: _searchQuery);
      setState(() {
        _books = books;
      });
    } catch (e) {
      print("Ocorreu um erro durante a sincronização: $e");
    } finally {
      setState(() => _isLoading = false);
    }
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
        title: const Text('Calibre Drive'),
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
        const PopupMenuItem(value: ViewMode.grid, child: Text('Grade')),
        const PopupMenuItem(
          value: ViewMode.listWithCover,
          child: Text('Lista com Capa'),
        ),
        const PopupMenuItem(
          value: ViewMode.compactList,
          child: Text('Lista Compacta'),
        ),
      ],
    );
  }

  Widget _buildBookDisplay() {
    if (_currentViewMode == ViewMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.7,
        ),
        itemCount: _books.length,
        itemBuilder: (context, index) => _buildGridItem(_books[index]),
      );
    } else {
      return ListView.builder(
        itemCount: _books.length,
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
  Widget _buildGridItem(BookModel book) =>
      Card(child: Center(child: Text(book.title)));
  Widget _buildListItem(BookModel book) =>
      ListTile(title: Text(book.title), subtitle: Text(book.author));
}
