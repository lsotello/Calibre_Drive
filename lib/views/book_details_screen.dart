import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/book_model.dart';
import '../services/database_service.dart';
import '../services/google_drive_service.dart';
import '../services/settings_service.dart';
import '../widgets/book_cover.dart';

class BookDetailsScreen extends StatefulWidget {
  final BookModel book;
  final Map<String, String> authHeaders;

  const BookDetailsScreen({
    super.key,
    required this.book,
    required this.authHeaders,
  });

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  final DatabaseService _dbService = DatabaseService();
  final GoogleDriveService _googleDriveService = GoogleDriveService();
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _googleDriveService.initializeWithHeaders(widget.authHeaders);
  }

  // --- MÉTODOS AUXILIARES DE CAMINHO ---

  String _getFileName() {
    String name = "${widget.book.title} - ${widget.book.author}.epub";
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  /// Centraliza a lógica de onde o arquivo deve estar
  Future<String> _getFinalPath() async {
    String? userPath = await SettingsService.getDownloadPath();
    String directoryPath;

    if (userPath != null && userPath.trim().isNotEmpty) {
      directoryPath = userPath;
    } else {
      final defaultDir = await getApplicationDocumentsDirectory();
      directoryPath = defaultDir.path;
    }
    return "$directoryPath/${_getFileName()}";
  }

  Future<bool> _checkIfFileExistsLocally() async {
    final path = await _getFinalPath();
    return File(path).exists();
  }

  // --- UI UTILS ---

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // --- LÓGICA DE DOWNLOAD ---

  Future<void> _handleDownload(String fileId) async {
    if (_isDownloading) return;

    final path = await SettingsService.getDownloadPath();
    if (path == null) {
      _showSnackBar(
        "Configure a pasta de livros nas configurações",
        isError: true,
      );
      return;
    }

    setState(() => _isDownloading = true);

    try {
      final fileName = _getFileName();
      String? userPath = await SettingsService.getDownloadPath();

      // Define a pasta base
      String directoryPath;
      if (userPath != null && userPath.trim().isNotEmpty) {
        directoryPath = userPath;
      } else {
        final defaultDir = await getApplicationDocumentsDirectory();
        directoryPath = defaultDir.path;
      }

      final file = await _googleDriveService.downloadBookFile(
        fileId,
        fileName,
        customPath: directoryPath,
      );

      if (file != null && await file.exists() && await file.length() > 0) {
        if (mounted) {
          setState(() {}); // Recarrega para mudar o ícone do botão
          _showSnackBar("Livro pronto para leitura!");
        }
      } else {
        throw "Erro ao processar arquivo baixado.";
      }
    } catch (e) {
      debugPrint("ERRO NO DOWNLOAD: $e");
      _showSnackBar("Falha no download: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // --- LÓGICA DE OPÇÕES (KINDLE / EXCLUIR) ---

  void _showFileOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                widget.book.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.tablet_android, color: Colors.orange),
              title: const Text("Enviar para Kindle / Compartilhar"),
              onTap: () {
                Navigator.pop(context);
                _sendToKindle();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text("Remover do dispositivo"),
              onTap: () {
                Navigator.pop(context);
                _confirmDeletion();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletion() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Excluir arquivo?"),
        content: const Text(
          "O arquivo será removido permanentemente do celular.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          TextButton(
            onPressed: () async {
              final path = await _getFinalPath();
              final file = File(path);
              if (await file.exists()) {
                await file.delete();
                if (mounted) setState(() {});
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text("EXCLUIR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _sendToKindle() async {
    final path = await _getFinalPath();
    final file = File(path);

    if (await file.exists()) {
      try {
        await Share.shareXFiles(
          [XFile(path)],
          subject: widget.book.title,
          text: 'Enviando ${widget.book.title} para leitura.',
        );
      } catch (e) {
        _showSnackBar("Erro ao compartilhar: $e", isError: true);
      }
    } else {
      _showSnackBar("Arquivo não encontrado localmente.", isError: true);
    }
  }

  String _cleanHtml(String html) {
    if (html.isEmpty) return "";
    return html
        .replaceAll(RegExp(r'<style([\s\S]*?)<\/style>'), '')
        .replaceAll(RegExp(r'style="[^"]*"'), '')
        .replaceAll(RegExp(r'<p>\s*<\/p>'), '')
        .replaceAll(RegExp(r'(<br\s*\/?>\s*){2,}', multiLine: true), '<br/>')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BookCover(
                        fileId: widget.book.coverId,
                        authHeaders: widget.authHeaders,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.book.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "por ${widget.book.author}",
                        style: TextStyle(color: Colors.grey[700], fontSize: 14),
                      ),
                      const SizedBox(height: 16),

                      // ÁREA DO BOTÃO DINÂMICO
                      FutureBuilder<String?>(
                        future: _dbService.getFileId(widget.book.id, 'epub'),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return const LinearProgressIndicator();
                          final fileId = snapshot.data!;

                          return FutureBuilder<bool>(
                            future: _checkIfFileExistsLocally(),
                            builder: (context, fileSnap) {
                              bool exists = fileSnap.data ?? false;
                              return ElevatedButton.icon(
                                onPressed: _isDownloading
                                    ? null
                                    : (exists
                                          ? _showFileOptions
                                          : () => _handleDownload(fileId)),
                                icon: _isDownloading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        exists
                                            ? Icons.menu_book
                                            : Icons.cloud_download,
                                      ),
                                label: Text(
                                  _isDownloading
                                      ? "BAIXANDO..."
                                      : (exists ? "LER AGORA" : "BAIXAR EPUB"),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: exists
                                      ? Colors.green[700]
                                      : null,
                                  foregroundColor: exists ? Colors.white : null,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            const Text(
              "Sinopse",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future: _dbService.getBookComment(widget.book.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                return Html(
                  data: _cleanHtml(snapshot.data ?? "Sem sinopse."),
                  style: {
                    "body": Style(
                      fontSize: FontSize(16.0),
                      lineHeight: LineHeight(1.5),
                    ),
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
