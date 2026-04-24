import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/database_service.dart';
import '../widgets/book_cover.dart';
import '../views/book_details_screen.dart';

// Definimos os modos de visualização
enum ViewMode { grid, listWithCover, compactList }

class BooksView extends StatefulWidget {
  final Map<String, String> authHeaders;
  final DatabaseService dbService;
  final bool isLoading; // Recebe o estado de carregamento da Home

  const BooksView({
    super.key,
    required this.authHeaders,
    required this.dbService,
    required this.isLoading,
  });

  @override
  State<BooksView> createState() => _BooksViewState();
}

class _BooksViewState extends State<BooksView> {
  ViewMode _currentViewMode = ViewMode.grid;
  String _searchQuery = "";
  List<BookModel> _books = [];

  @override
  void initState() {
    super.initState();
    _performSearch(); // Busca inicial
  }

  // IMPORTANTE: Se a Home terminar de sincronizar, precisamos atualizar a lista aqui
  @override
  void didUpdateWidget(covariant BooksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se o estado de carregamento mudou de TRUE para FALSE,
    // significa que a sincronia terminou. Hora de atualizar a lista!
    if (oldWidget.isLoading && !widget.isLoading) {
      _performSearch();
    }
  }

  Future<void> _performSearch() async {
    final books = await widget.dbService.searchBooks(query: _searchQuery);
    setState(() {
      _books = books;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A AppBar agora é exclusiva desta aba!
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Meus Livros'),
            Text(
              '${_books.length} títulos',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [_buildViewModeSelector()],
        bottom: _buildSearchAndFilterBar(),
      ),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBookDisplay(),
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

  PreferredSizeWidget _buildSearchAndFilterBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          onChanged: (value) {
            setState(() => _searchQuery = value);
            _performSearch();
          },
          decoration: InputDecoration(
            hintText: 'Buscar por título, autor ou série...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _showFilterSheet(),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Widget _buildGridItem(BookModel book) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToDetails(book),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: BookCover(
                  fileId: book.coverId,
                  authHeaders: widget.authHeaders,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
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
                    authHeaders: widget.authHeaders,
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

      onTap: () => _navigateToDetails(book),
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

  void _navigateToDetails(BookModel book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            BookDetailsScreen(book: book, authHeaders: widget.authHeaders),
      ),
    );
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
}
