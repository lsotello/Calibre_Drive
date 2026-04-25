class BookModel {
  final int id;
  final String title;
  final String path;
  final String author;
  final String? series;
  final double seriesIndex;
  final List<String> formats;
  final String? coverId;
  final String readingStatus;

  BookModel({
    required this.id,
    required this.title,
    required this.path,
    required this.author,
    this.series,
    required this.seriesIndex,
    this.formats = const [],
    this.coverId,
    this.readingStatus = 'pending',
  });

  // Converte o mapa do SQLite para o nosso objeto Dart
  factory BookModel.fromMap(
    Map<String, dynamic> map,
    List<String> formats, {
    String? coverId,
    String? readingStatus,
  }) {
    return BookModel(
      id: map['id'] ?? 0,
      title: map['title']?.toString() ?? 'Sem Título', // Segurança contra nulo
      path: map['path']?.toString() ?? '', // Segurança contra nulo
      author: map['author_name']?.toString() ?? 'Autor Desconhecido',
      series: map['series_name']?.toString(),
      seriesIndex: map['series_index'] != null
          ? (double.tryParse(map['series_index'].toString()) ?? 0.0)
          : 0.0,
      formats: formats,
      readingStatus:
          map['reading_status']?.toString() ?? readingStatus ?? 'pending',
      coverId: coverId ?? map['cover_id']?.toString() ?? '',
    );
  }
}
