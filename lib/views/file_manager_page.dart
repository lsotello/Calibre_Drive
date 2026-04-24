import 'dart:io';
import 'package:calibre_drive/models/book_model.dart';
import 'package:calibre_drive/widgets/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';

class FileManagerPage extends StatefulWidget {
  final String directoryPath;
  final Map<String, String> authHeaders;

  const FileManagerPage({
    super.key,
    required this.directoryPath,
    required this.authHeaders,
  });

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  final DatabaseService _dbService = DatabaseService();
  List<FileSystemEntity> _files = [];
  final Map<String, String> _titleToCoverPath =
      {}; // Mapa: "Título" -> "Caminho/da/Capa.jpg"
  final Set<int> _selectedIndices = {};
  bool _isLoading = true;
  int _totalDirectorySize = 0;
  Map<String, BookModel> _booksMap = {};

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    setState(() {
      _isLoading = true;
      _selectedIndices.clear();
    });

    try {
      // 1. Pega todos os livros do banco para cruzar com os arquivos locais
      final allBooks = await _dbService.searchBooks(query: "");

      // Criamos um mapa para busca rápida: "Título - Autor" -> BookModel
      final Map<String, BookModel> fileToBookMap = {};
      for (var book in allBooks) {
        String key = "${book.title} - ${book.author}";
        fileToBookMap[key] = book;
      }

      final dir = Directory(widget.directoryPath);
      if (await dir.exists()) {
        final epubFiles = dir
            .listSync()
            .where((file) => file.path.toLowerCase().endsWith('.epub'))
            .toList();

        int totalSize = 0;
        for (var f in epubFiles) {
          totalSize += f.statSync().size;
        }

        setState(() {
          _files = epubFiles;
          // Agora temos acesso ao BookModel completo para cada arquivo
          _totalDirectorySize = totalSize;
          _booksMap = fileToBookMap; // Salve isso no estado
        });
      }
    } catch (e) {
      debugPrint("Erro: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ... (métodos _formatSize, _calculateSelectedSize, _toggleSelection, _deleteSelected permanecem iguais)

  @override
  Widget build(BuildContext context) {
    bool isMultiSelect = _selectedIndices.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: isMultiSelect
            ? Text("${_selectedIndices.length} selecionados")
            : const Text("Gerenciar Arquivos"),
        actions: [
          if (isMultiSelect)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _deleteSelected,
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshFiles,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildStorageSummary(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                ? const Center(child: Text("Nenhum livro encontrado."))
                : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final isSelected = _selectedIndices.contains(index);
                      final stats = file.statSync();

                      final fullFileName = file.path.split('/').last;
                      final fileNameNoExt = fullFileName.replaceAll(
                        '.epub',
                        '',
                      );
                      final book = _booksMap[fileNameNoExt];

                      return ListTile(
                        selected: isSelected,
                        onLongPress: () => _toggleSelection(index),
                        onTap:
                            (_selectedIndices
                                .isNotEmpty) // Se houver seleção, clica para marcar
                            ? () => _toggleSelection(index)
                            : null, // Aqui você pode depois colocar para abrir o livro
                        leading: Stack(
                          children: [
                            // Usamos o seu widget de capa padrão
                            SizedBox(
                              width: 45,
                              height: 65,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: book != null
                                    ? BookCover(
                                        fileId: book.coverId,
                                        authHeaders: widget.authHeaders,
                                      )
                                    : Container(
                                        color: Colors.grey[200],
                                        child: const Icon(
                                          Icons.book,
                                          color: Colors.grey,
                                        ),
                                      ),
                              ),
                            ),
                            // Overlay de seleção
                            if (isSelected)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          fullFileName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          "${_formatSize(stats.size)} • ${DateFormat('dd/MM/yy').format(stats.modified)}",
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),
          if (_selectedIndices.isNotEmpty) _buildSelectionActionSheet(),
        ],
      ),
    );
  }

  // ... (restante dos widgets de suporte: _buildStorageSummary, _buildSelectionActionSheet)

  // No build, onde exibimos o resumo de espaço:
  Widget _buildStorageSummary() {
    int selectedSize = _calculateSelectedSize();

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 0,
      color: Colors.blue.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Ocupado localmente",
                  style: TextStyle(color: Colors.blueGrey),
                ),
                Text(
                  _formatSize(_totalDirectorySize),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            if (_selectedIndices.isNotEmpty) ...[
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${_selectedIndices.length} selecionados",
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  Text(
                    "Libera: ${_formatSize(selectedSize)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Converte bytes para uma string legível (KB, MB, GB)
  String _formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (bytes.toString().length - 1) ~/ 3;
    double size = bytes / (1024 * (i == 1 ? 1 : (i == 2 ? 1024 : 1048576)));
    return "${size.toStringAsFixed(1)} ${suffixes[i]}";
  }

  /// Soma o tamanho de todos os arquivos selecionados
  int _calculateSelectedSize() {
    int size = 0;
    for (int index in _selectedIndices) {
      if (index < _files.length) {
        size += _files[index].statSync().size;
      }
    }
    return size;
  }

  /// Alterna a seleção de um item (adiciona ou remove do Set)
  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIndices.length;
    final sizeToRelease = _formatSize(_calculateSelectedSize());

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Excluir $count itens?"),
        content: Text("Isso liberará $sizeToRelease de espaço no dispositivo."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCELAR"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "EXCLUIR TUDO",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Deletamos do fim para o começo para não perder o índice da lista
        List<int> sortedIndices = _selectedIndices.toList()
          ..sort((a, b) => b.compareTo(a));

        for (int index in sortedIndices) {
          await _files[index].delete();
        }

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("$count arquivos removidos.")));
        }
        _refreshFiles(); // Atualiza a lista e o tamanho total
      } catch (e) {
        debugPrint("Erro ao deletar: $e");
      }
    }
  }

  Widget _buildSelectionActionSheet() {
    int selectedSize = _calculateSelectedSize();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${_selectedIndices.length} selecionados",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "Liberar: ${_formatSize(selectedSize)}",
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_forever),
              label: const Text("EXCLUIR"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
