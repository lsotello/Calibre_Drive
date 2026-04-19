import 'package:flutter/material.dart';
import '../models/book_model.dart';

class BookDetailsScreen extends StatelessWidget {
  final BookModel book;

  const BookDetailsScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.title)),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Capa Grande com Hero Animation para transição suave
            Hero(
              tag: 'book-${book.id}',
              child: Container(
                height: 300,
                width: 200,
                margin: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.book,
                  size: 100,
                ), // Substituir por Image futuramente
              ),
            ),

            Text(
              book.title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            Text(book.author, style: Theme.of(context).textTheme.titleMedium),

            const Divider(height: 40),

            // Botão Principal de Ação
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: () => _handleSendToKindle(context),
                icon: const Icon(Icons.send),
                label: const Text('ENVIAR PARA KINDLE'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSendToKindle(BuildContext context) {
    // 1. Mostrar loading
    // 2. Baixar o arquivo EPUB do Drive
    // 3. Usar Share.shareXFiles()
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparando arquivo para o Kindle...')),
    );
  }
}
