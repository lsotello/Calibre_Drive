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

  // --- MÉTODOS AUXILIARES (LÓGICA DE ARQUIVO) ---

  String _getFileName() {
    String name = "${widget.book.title} - ${widget.book.author}.epub";
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

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
      ),
    );
  }

  // --- LÓGICA DE DOWNLOAD E OPÇÕES ---

  Future<void> _handleDownload(String fileId) async {
    if (_isDownloading) return;
    final pathConfig = await SettingsService.getDownloadPath();
    if (pathConfig == null) {
      _showSnackBar(
        "Configure a pasta de livros nas configurações",
        isError: true,
      );
      return;
    }

    setState(() => _isDownloading = true);
    try {
      final fileName = _getFileName();
      final file = await _googleDriveService.downloadBookFile(
        fileId,
        fileName,
        customPath: pathConfig,
      );

      if (file != null && await file.exists()) {
        setState(() {});
        _showSnackBar("Livro pronto para leitura!");
      }
    } catch (e) {
      _showSnackBar("Falha no download: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showFileOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20), // Use Radius.circular aqui
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
        content: const Text("O arquivo será removido do celular."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          TextButton(
            onPressed: () async {
              final file = File(await _getFinalPath());
              if (await file.exists()) await file.delete();
              if (mounted) {
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: const Text("EXCLUIR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _sendToKindle() async {
    final path = await _getFinalPath();
    if (await File(path).exists()) {
      await Share.shareXFiles([XFile(path)], subject: widget.book.title);
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

  // --- INTERFACE (O MIX DAS DUAS VERSÕES) ---

  @override
  Widget build(BuildContext context) {
    final book = widget.book;

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
                // Capa (Vinda da versão atual)
                SizedBox(
                  width: 120,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BookCover(
                        fileId: book.coverId,
                        authHeaders: widget.authHeaders,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Informações (Recuperando a Série da versão anterior)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "por ${book.author}",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: Colors.grey[700]),
                      ),

                      // REINSERIDO: Informação de Série
                      if (book.series != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Série: ${book.series}",
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // REINSERIDO: Badge do ID Calibre
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "ID Calibre: #${book.id}",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(height: 32),

            // Botão de Download/Ação (Dinâmico da versão Atual)
            FutureBuilder<String?>(
              future: _dbService.getFileId(book.id, 'epub'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final fileId = snapshot.data!;

                return FutureBuilder<bool>(
                  future: _checkIfFileExistsLocally(),
                  builder: (context, fileSnap) {
                    bool exists = fileSnap.data ?? false;
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
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
                                exists ? Icons.menu_book : Icons.cloud_download,
                              ),
                        label: Text(
                          _isDownloading
                              ? "BAIXANDO..."
                              : (exists ? "OPÇÕES DO ARQUIVO" : "BAIXAR EPUB"),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: exists ? Colors.green[700] : null,
                          foregroundColor: exists ? Colors.white : null,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            const Divider(height: 32),

            const Text(
              "Sinopse",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Sinopse com o Estilo Refinado da versão anterior
            FutureBuilder<String?>(
              future: _dbService.getBookComment(book.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Html(
                  data: _cleanHtml(
                    snapshot.data ?? "Nenhuma sinopse disponível.",
                  ),
                  style: {
                    "body": Style(
                      fontSize: FontSize(16.0),
                      lineHeight: LineHeight(1.6),
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                    ),
                    "p": Style(margin: Margins.only(bottom: 8)),
                  },
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
