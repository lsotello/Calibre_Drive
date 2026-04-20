class BookModel {
  final int id;
  final String title;
  final String path;
  final String author;
  final String? series;
  final double? seriesIndex;
  final List<String> formats;
  final String? coverId;

  BookModel({
    required this.id,
    required this.title,
    required this.path,
    required this.author,
    this.series,
    this.seriesIndex,
    this.formats = const [],
    this.coverId,
  });

  // Converte o mapa do SQLite para o nosso objeto Dart
  factory BookModel.fromMap(
    Map<String, dynamic> map,
    List<String> formats, {
    String? coverId,
  }) {
    return BookModel(
      id: map['id'],
      title: map['title'],
      path: map['path'],
      author: map['author_name'] ?? 'Autor Desconhecido',
      series: map['series_name'],
      seriesIndex: map['series_index'],
      formats: formats,
      coverId: coverId, // O ID que veio da sua varredura/cache
    );
  }
}
