import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  // Chaves constantes para evitar erros de digitação
  static const String _keyDownloadPath = 'download_path';
  static const String _keyBackupPath = 'backup_path';
  static const String _keyLastSync = 'last_sync_date';
  static const String _keyDbFileId = 'db_file_id';

  // Métodos de Gravação
  static Future<void> setDownloadPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDownloadPath, path);
  }

  static Future<void> setBackupPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBackupPath, path);
  }

  static Future<void> setLastSync(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSync, date);
  }

  // Métodos de Leitura
  static Future<String?> getDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    String? path = prefs.getString(_keyDownloadPath);
    if (path == null || path.trim().isEmpty) return null;
    return path;
  }

  static Future<String?> getBackupPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBackupPath);
  }

  static Future<String?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSync);
  }

  static Future<void> setDbFileId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDbFileId, id);
  }

  static Future<String?> getDbFileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDbFileId);
  }

  // No seu SettingsService.dart
  static Future<String> getEffectiveDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    String? customPath = prefs.getString(_keyDownloadPath);

    // Se a String for nula, estiver vazia ou for apenas espaços
    if (customPath == null || customPath.trim().isEmpty) {
      // Retorna o caminho padrão do sistema (Plano B)
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    }

    return customPath;
  }

  static Future<String> getDatabaseLocalPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return "${directory.path}/metadata.db";
  }
}
