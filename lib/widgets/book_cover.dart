import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class BookCover extends StatelessWidget {
  final String? fileId;
  final Map<String, String> authHeaders;

  const BookCover({super.key, this.fileId, required this.authHeaders});

  @override
  Widget build(BuildContext context) {
    if (fileId == null) {
      return Container(
        color: Colors.grey[300],
        child: const Icon(Icons.book, size: 50),
      );
    }

    return CachedNetworkImage(
      //cacheKey: fileId,
      imageUrl: "https://www.googleapis.com/drive/v3/files/$fileId?alt=media",
      httpHeaders: authHeaders,
      memCacheHeight: 300, // Redimensiona para 300px de altura em memória
      maxWidthDiskCache: 400, // Opcional: economiza espaço no disco
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (context, url, error) {
        print("Erro na capa: $error"); // Ajuda a debugar no console
        return Container(
          color: Colors.grey[300],
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.book, color: Colors.grey),
              Text("Sem capa", style: TextStyle(fontSize: 10)),
            ],
          ),
        );
      },
    );
  }
}
