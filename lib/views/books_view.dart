import 'package:calibre_drive/utils/logger.dart';
import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/database_service.dart';
import '../widgets/book_cover.dart';
import '../views/book_details_screen.dart';

enum ViewMode { grid, listWithCover, compactList }

class BooksView extends StatefulWidget {
  final Map<String, String> authHeaders;
  final DatabaseService dbService;
  final bool isLoading;
  final Map<String, String>? initialFilters;

  const BooksView({
    super.key,
    required this.authHeaders,
    required this.dbService,
    required this.isLoading,
    this.initialFilters,
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
    _performSearch();
  }

  @override
  void didUpdateWidget(covariant BooksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading && !widget.isLoading) {
      _performSearch();
    }
  }

  Future<void> _performSearch() async {
    // Remova todas as verificações de "isCalibreReady" daqui.
    // Deixe o searchBooks cuidar da abertura automática.
    String? seriesFilter = widget.initialFilters?['series'];
    String? authorFilter = widget.initialFilters?['author'];

    final books = await widget.dbService.searchBooks(
      query: _searchQuery,
      seriesFilter: seriesFilter,
      authorFilter: authorFilter,
    );

    if (mounted) {
      setState(() {
        _books = books;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      // Esticamos os filhos para não haver re-cálculo de largura
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.0, horizontal: 20),
          child: Text(
            "Exibindo ${_books.length} livros",
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
        // Forçamos uma altura fixa e exata para o Header
        SizedBox(height: 70, child: _buildHeader()),

        if (widget.isLoading) const LinearProgressIndicator(minHeight: 2),

        Expanded(
          child: _books.isEmpty && widget.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildBookDisplay(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (value) {
                _searchQuery = value;
                _performSearch();
              },
              decoration: InputDecoration(
                hintText: 'Buscar título, autor...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                // Mantemos o preenchimento interno fixo
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          _buildViewModeSelector(),
        ],
      ),
    );
  }

  Widget _buildViewModeSelector() {
    return PopupMenuButton<ViewMode>(
      icon: const Icon(Icons.grid_view),
      onSelected: (mode) => setState(() => _currentViewMode = mode),
      itemBuilder: (context) => [
        _buildPopupItem(ViewMode.grid, Icons.grid_on, 'Grade'),
        _buildPopupItem(
          ViewMode.listWithCover,
          Icons.format_list_bulleted,
          'Lista + Capa',
        ),
        _buildPopupItem(ViewMode.compactList, Icons.reorder, 'Compacta'),
      ],
    );
  }

  // --- MANTENHA SEUS MÉTODOS EXISTENTES ABAIXO ---
  // _buildBookDisplay(), _buildGridItem(), _buildListItem(), _buildPopupItem(), _navigateToDetails()

  Widget _buildBookDisplay() {
    if (_currentViewMode == ViewMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _books.length,
        itemBuilder: (context, index) => _buildGridItem(_books[index]),
      );
    }
    return ListView.separated(
      itemCount: _books.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildListItem(_books[index]),
    );
  }

  Widget _buildGridItem(BookModel book) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToDetails(book),
        onLongPress: () => _showStatusMenu(book),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                // Stack permite sobrepor o ícone à capa
                children: [
                  Positioned.fill(
                    child: BookCover(
                      fileId: book.coverId,
                      authHeaders: widget.authHeaders,
                    ),
                  ),
                  // Ícone flutuante no topo direito
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                      child: _buildStatusIndicator(book.readingStatus),
                    ),
                  ),
                  if (book.seriesIndex > 0)
                    Positioned(
                      top: 4,
                      left: 4, // Lado oposto ao status
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white24, width: 0.5),
                        ),
                        child: Text(
                          // Remove o .0 se for número inteiro (ex: 1.0 vira 1)
                          book.seriesIndex.toStringAsFixed(
                            book.seriesIndex % 1 == 0 ? 0 : 1,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(BookModel book) {
    bool isCompact = _currentViewMode == ViewMode.compactList;
    return ListTile(
      dense: isCompact,
      leading: isCompact
          ? const Icon(Icons.book)
          : SizedBox(
              width: 40,
              child: BookCover(
                fileId: book.coverId,
                authHeaders: widget.authHeaders,
              ),
            ),
      title: Text(book.title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(book.author, style: const TextStyle(fontSize: 12)),
      // Mostra o status do lado direito
      trailing: _buildStatusIndicator(book.readingStatus),
      onTap: () => _navigateToDetails(book),
      onLongPress: () => _showStatusMenu(book),
    );
  }

  PopupMenuItem<ViewMode> _buildPopupItem(
    ViewMode mode,
    IconData icon,
    String label,
  ) {
    bool isSelected = _currentViewMode == mode;

    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, color: isSelected ? Colors.blue : Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : null,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
          ),
          if (isSelected) const Icon(Icons.check, color: Colors.blue, size: 16),
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

  Widget _buildStatusIndicator(String status) {
    switch (status) {
      case 'reading':
        return const Icon(Icons.play_circle_fill, color: Colors.blue, size: 18);
      case 'finished':
        return const Icon(Icons.check_circle, color: Colors.green, size: 18);
      default:
        return const SizedBox.shrink(); // 'pending' não mostra nada
    }
  }

  void _showStatusMenu(BookModel book) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_circle_fill, color: Colors.blue),
            title: const Text('Marcar como "Lendo"'),
            onTap: () => _changeBookStatus(book, 'reading'),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text('Marcar como "Lido"'),
            onTap: () => _changeBookStatus(book, 'finished'),
          ),
          ListTile(
            leading: const Icon(Icons.circle_outlined, color: Colors.grey),
            title: const Text('Remover Status (Pendente)'),
            onTap: () => _changeBookStatus(book, 'pending'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Função que executa a troca e atualiza a tela
  Future<void> _changeBookStatus(BookModel book, String newStatus) async {
    Navigator.pop(context); // Fecha o menu
    await widget.dbService.updateReadingStatus(book.id, newStatus);
    _performSearch(); // Recarrega a lista para mostrar o novo ícone
  }
}
