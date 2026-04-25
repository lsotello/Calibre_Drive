import 'package:flutter/material.dart';
import '../services/database_service.dart';

class CategoryView extends StatelessWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> future;
  final Function(String) onTap;

  const CategoryView({
    super.key,
    required this.title,
    required this.future,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final items = snapshot.data!;
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              title: Text(item['name']),
              trailing: Chip(
                label: Text(item['count'].toString()),
                labelStyle: const TextStyle(fontSize: 10),
              ),
              onTap: () => onTap(item['name']),
            );
          },
        );
      },
    );
  }
}
