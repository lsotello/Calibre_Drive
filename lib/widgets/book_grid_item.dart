import 'package:flutter/material.dart';
import '../models/book_model.dart';

class BookGridItem extends StatelessWidget {
  final BookModel book;
  final bool isDownloaded; // Exemplo de status
  final VoidCallback onTap;

  const BookGridItem({
    super.key,
    required this.book,
    required this.onTap,
    this.isDownloaded = false,
  });

  @override
  Widget build(BuildContext context) {
    // Usamos um InkWell para dar feedback visual do toque (efeito Ripple)
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        clipBehavior: Clip
            .antiAlias, // Garante que a imagem não saia da borda arredondada
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ÁREA DA CAPA (Gerencia o AspectRatio 0.7 clássico de capas)
            Expanded(
              child: AspectRatio(
                aspectRatio: 0.7,
                child: Container(
                  color: Colors.grey[300], // Fundo para enquanto carrega
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // IMAGEM (Aqui usaremos o CachedNetworkImage depois)
                      const Icon(Icons.book, size: 50, color: Colors.grey),

                      // ÍCONE DE STATUS (Nuvem ou Downloaded)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white70,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isDownloaded
                                ? Icons.offline_pin
                                : Icons.cloud_download_outlined,
                            size: 16,
                            color: isDownloaded
                                ? Colors.green[700]
                                : Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ÁREA DO TEXTO (Título e Autor)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize:
                    MainAxisSize.min, // Ocupa o mínimo de espaço vertical
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
