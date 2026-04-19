import 'package:flutter/material.dart';
import '../models/book_model.dart';

class BookListItem extends StatelessWidget {
  final BookModel book;
  final bool isDownloaded;
  final VoidCallback onTap;

  const BookListItem({
    super.key,
    required this.book,
    required this.onTap,
    this.isDownloaded = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ÁREA DA CAPA (Pequena à esquerda)
            Container(
              width: 60,
              height: 85, // AspectRatio próximo a 0.7
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.book, color: Colors.grey),
            ),
            const SizedBox(width: 16),

            // ÁREA DO TEXTO (Expande para o resto da largura)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(book.author, style: const TextStyle(fontSize: 14)),
                  if (book.series != null)
                    Text(
                      '${book.series} #${book.seriesIndex?.toInt()}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                ],
              ),
            ),

            // ÍCONE DE STATUS
            Icon(
              isDownloaded ? Icons.offline_pin : Icons.cloud_download_outlined,
              size: 20,
              color: isDownloaded ? Colors.green : Colors.blue,
            ),
          ],
        ),
      ),
    );
  }
}
