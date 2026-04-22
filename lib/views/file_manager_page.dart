import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class FileManagerPage extends StatefulWidget {
  final String directoryPath;

  const FileManagerPage({super.key, required this.directoryPath});

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  List<FileSystemEntity> _files = [];
  final Set<String> _selectedPaths = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  // Lê os arquivos da pasta configurada
  void _refreshFiles() {
    final dir = Directory(widget.directoryPath);

    if (!dir.existsSync()) {
      print("DEBUG: Pasta não encontrada: ${widget.directoryPath}");
      return;
    }

    // 1. Filtramos e já transformamos em uma lista de objetos 'File'
    // O .whereType<File>() é a chave para o Dart reconhecer os métodos de arquivo
    final List<File> filesFound = dir.listSync().whereType<File>().where((
      file,
    ) {
      final path = file.path.toLowerCase();
      return path.endsWith('.epub') ||
          path.endsWith('.pdf') ||
          path.endsWith('.mobi') ||
          path.endsWith('.azw3');
    }).toList();

    // 2. Ordenação (agora o tipo File é garantido)
    filesFound.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );

    setState(() {
      _files = filesFound;
    });
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) _isSelectionMode = false;
      } else {
        _selectedPaths.add(path);
        _isSelectionMode = true;
      }
    });
  }

  // Exclui os arquivos selecionados
  Future<void> _deleteSelected() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Excluir arquivos?"),
        content: Text(
          "Você está prestes a apagar ${_selectedPaths.length} arquivo(s).",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Excluir", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (String path in _selectedPaths) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      setState(() {
        _selectedPaths.clear();
        _isSelectionMode = false;
      });
      _refreshFiles();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Arquivos removidos!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? "${_selectedPaths.length} selecionados"
              : "Meus Downloads",
        ),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              onPressed: _deleteSelected,
            ),
        ],
      ),
      body: _files.isEmpty
          ? const Center(child: Text("Nenhum livro baixado nesta pasta."))
          : ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final file = _files[index];
                final fileName = p.basename(file.path);
                final isSelected = _selectedPaths.contains(file.path);

                return ListTile(
                  leading: Icon(
                    Icons.book,
                    color: isSelected ? Colors.blue : Colors.grey,
                  ),
                  title: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    "${(File(file.path).lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB",
                  ),
                  trailing: _isSelectionMode
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection(file.path),
                        )
                      : null,
                  selected: isSelected,
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(file.path);
                    } else {
                      // Se não estiver em modo de seleção, um clique curto pode abrir o arquivo
                      // ou simplesmente entrar no modo de seleção.
                      _toggleSelection(file.path);
                    }
                  },
                  onLongPress: () => _toggleSelection(file.path),
                );
              },
            ),
    );
  }
}
