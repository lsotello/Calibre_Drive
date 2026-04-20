import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/database_service.dart';
import '../widgets/book_cover.dart';
import 'package:flutter_html/flutter_html.dart';

class BookDetailsScreen extends StatelessWidget {
  final BookModel book;
  final Map<String, String> authHeaders;

  const BookDetailsScreen({
    super.key,
    required this.book,
    required this.authHeaders,
  });

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
                SizedBox(
                  width: 120,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BookCover(
                        fileId: book.coverId,
                        authHeaders: authHeaders,
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
                      if (book.series != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Série: ${book.series}",
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // O ID DO LIVRO NO CALIBRE
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

            // Seção de Sinopse
            const Text(
              "Sinopse",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future: DatabaseService().getBookComment(
                book.id,
              ), // Buscando do DB
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                final comment = snapshot.data ?? "Nenhuma sinopse disponível.";
                // Nota: Se o texto vier em HTML, usaremos um plugin depois para renderizar
                return Html(
                  data: _cleanHtml(comment),
                  style: {
                    // Estilizamos a tag "body" para afetar todo o texto
                    "body": Style(
                      fontSize: FontSize(16.0),
                      lineHeight: LineHeight(1.6),
                      //textAlign: TextAlign.justify,
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                      //color: Colors.black87,
                    ),
                    // Podemos estilizar tags específicas se o Calibre as usar
                    //"b": Style(fontWeight: FontWeight.bold),
                    //"i": Style(fontStyle: FontStyle.italic),
                    // Remove margens excessivas de parágrafos e divisões
                    "p": Style(margin: Margins.only(bottom: 8)),
                    "div": Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                    ),
                    "br": Style(
                      display: Display.none,
                    ), // Opcional: se houver muitos <br><br>
                  },
                );
              },
            ),
            const SizedBox(height: 32),

            // Botão de Download (Próxima etapa)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  /* Lógica de download virá aqui */
                },
                icon: const Icon(Icons.download),
                label: const Text("BAIXAR LIVRO"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _cleanHtml(String html) {
    if (html.isEmpty) return "";

    return html
        // 1. Remove tags de estilo inteiras (<style>...</style>)
        .replaceAll(RegExp(r'<style([\s\S]*?)<\/style>'), '')
        // 2. REMOVE ATRIBUTOS DE ESTILO (O culpado do espaçamento)
        // Isso transforma <div style="margin: 50px"> em apenas <div>
        .replaceAll(RegExp(r'style="[^"]*"'), '')
        // 3. Remove tags de parágrafo vazias ou com apenas espaços
        .replaceAll(RegExp(r'<p>\s*<\/p>'), '')
        // 4. Transforma múltiplos <br> em apenas um
        .replaceAll(
          RegExp(r'(<br\s*\/?>\s*){2Sync,}', multiLine: true),
          '<br/>',
        )
        .trim();
  }
}
