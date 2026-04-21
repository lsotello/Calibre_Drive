import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/book_model.dart';
import '../services/database_service.dart';
import '../services/google_drive_service.dart'; // Importante adicionar este
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
  @override
  void initState() {
    super.initState();
    // Inicializa o serviço com as credenciais que a tela recebeu
    _googleDriveService.initializeWithHeaders(widget.authHeaders);
  }

  // Inicializamos os serviços aqui dentro do State
  bool _isDownloading = false;

  final DatabaseService _dbService = DatabaseService();
  final GoogleDriveService _googleDriveService = GoogleDriveService();

  String _getFileName() {
    // Criamos o nome combinando Título e Autor para bater com o padrão do Calibre
    String fullPath = "${widget.book.title} - ${widget.book.author}.epub";

    // Limpamos apenas caracteres proibidos pelo sistema operacional
    return fullPath.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<bool> _checkIfFileExistsLocally() async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = "${directory.path}/${_getFileName()}"; // Usa a função
    final exists = await File(filePath).exists();
    return exists;
  }

  // Função para lidar com o download
  Future<void> _handleDownload(String fileId) async {
    // Evita cliques duplos enquanto já está baixando
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    print("--- INICIANDO DOWNLOAD ---");
    print("Drive ID: $fileId");

    try {
      // 1. Limpa o nome do arquivo para evitar erros de Sistema Operacional
      final fileName = _getFileName();
      print("Salvando como: $fileName");

      // 2. Chama o serviço de download
      //final file = await _googleDriveService.downloadBookFile(fileId, fileName);

      // Para este bloco temporário:
      print("Debug: Chamando o serviço agora...");
      final file = await _googleDriveService
          .downloadBookFile(fileId, fileName)
          .catchError((error) {
            print("ERRO DISPARADO NA ENTRADA DA FUNÇÃO: $error");
            return null;
          });

      if (file != null) {
        final exists = await file.exists();
        final size = await file.length();

        print("Caminho local: ${file.path}");
        print("Tamanho do arquivo: $size bytes");

        if (exists && size > 0) {
          if (mounted) {
            // setState aqui força o botão a ficar VERDE imediatamente
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Livro pronto para leitura!"),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw "Arquivo criado, mas está vazio (0 bytes).";
        }
      } else {
        throw "Não foi possível receber os dados do Google Drive.";
      }
    } catch (e) {
      print("ERRO NO DOWNLOAD: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Falha: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
        print("--- PROCESSO FINALIZADO ---");
      }
    }
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
            // Cabeçalho com Capa e Info básica
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LADO ESQUERDO: CAPA
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

                // LADO DIREITO: INFOS E BOTÃO
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Linha do Título + ID
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              widget.book.title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                            ),
                          ),
                          // ID do Calibre (Badge discreto)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "ID: ${widget.book.id}",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "por ${widget.book.author}",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: Colors.grey[700], fontSize: 14),
                      ),
                      if (widget.book.series != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Série: ${widget.book.series}",
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // ÁREA DE DOWNLOAD E STATUS
                      FutureBuilder<String?>(
                        future: _dbService.getFileId(widget.book.id, 'epub'),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const SizedBox(
                              width: 20,
                              child: LinearProgressIndicator(),
                            );
                          }

                          final fileId = snapshot.data;
                          if (fileId == null) {
                            return const Text(
                              "EPUB não disponível",
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            );
                          }

                          // Verificamos se o arquivo já existe localmente
                          return FutureBuilder<bool>(
                            future: _checkIfFileExistsLocally(),
                            builder: (context, fileSnap) {
                              bool exists = fileSnap.data ?? false;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ElevatedButton.icon(
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
                                          : (exists
                                                ? "LER AGORA"
                                                : "BAIXAR EPUB"),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: exists
                                          ? Colors.green[700]
                                          : null,
                                      foregroundColor: exists
                                          ? Colors.white
                                          : null,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        exists
                                            ? Icons.check_circle
                                            : Icons.cloud_done_outlined,
                                        size: 14,
                                        color: exists
                                            ? Colors.green
                                            : Colors.blue,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        exists
                                            ? "No dispositivo"
                                            : "Disponível no Drive",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: exists
                                              ? Colors.green[800]
                                              : Colors.blue[800],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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

            // Seção de Sinopse
            const Text(
              "Sinopse",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future: _dbService.getBookComment(widget.book.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final comment = snapshot.data ?? "Nenhuma sinopse disponível.";
                return Html(
                  data: _cleanHtml(comment),
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

  String _cleanHtml(String html) {
    if (html.isEmpty) return "";
    return html
        .replaceAll(RegExp(r'<style([\s\S]*?)<\/style>'), '')
        .replaceAll(RegExp(r'style="[^"]*"'), '')
        .replaceAll(RegExp(r'<p>\s*<\/p>'), '')
        .replaceAll(RegExp(r'(<br\s*\/?>\s*){2,}', multiLine: true), '<br/>')
        .trim();
  }

  void _showFileOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize
                .min, // Faz a janela ocupar apenas o espaço necessário
            children: [
              Text(
                widget.book.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Divider(),
              // Opção 2: ENVIAR PARA KINDLE
              ListTile(
                leading: const Icon(Icons.tablet_android, color: Colors.orange),
                title: const Text("Enviar para Kindle"),
                onTap: () {
                  Navigator.pop(context);
                  _sendToKindle(); // Vamos preparar essa função abaixo
                },
              ),

              // Opção 3: EXCLUIR ARQUIVO
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Remover o arquivo deste dispositivo"),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeletion(); // Vamos preparar essa função abaixo
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeletion() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Excluir arquivo?"),
        content: const Text("O arquivo será removido do seu celular."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCELAR"),
          ),
          TextButton(
            onPressed: () async {
              final directory = await getApplicationDocumentsDirectory();
              final file = File("${directory.path}/${_getFileName()}");
              if (await file.exists()) {
                await file.delete();
                setState(() {}); // Atualiza o botão para "BAIXAR" novamente
              }
              Navigator.pop(context);
            },
            child: const Text("EXCLUIR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _sendToKindle() async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = "${directory.path}/${_getFileName()}";
    final file = File(filePath);

    if (await file.exists()) {
      // Certifique-se de que XFile está sendo importado de share_plus
      final xFile = XFile(filePath);

      try {
        // Use await e verifique se não há nenhum 'share' (sem o XFiles) no código
        await Share.shareXFiles(
          [xFile],
          subject: widget.book.title, // Assunto para e-mail/Kindle
          text: 'Enviando livro para o Kindle',
        );
      } catch (e) {
        print("Erro ao compartilhar: $e");
      }
    }
  }
}
