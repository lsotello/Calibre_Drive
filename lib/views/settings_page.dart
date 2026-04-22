import 'dart:io';
import 'package:calibre_drive/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../services/google_drive_service.dart';
import '../services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _downloadPath = "Não configurado";
  String _backupPath = "Não configurado";
  String _localSyncDateDisplay = "N/A";
  String _driveSyncDateDisplay = "Clique para verificar";

  final GoogleDriveService _googleDriveService = GoogleDriveService();

  @override
  void initState() {
    super.initState();
    _loadPaths();

    // Tenta restaurar a conexão sem o usuário perceber
    _googleDriveService.restoreSession().then((sucesso) {
      if (!sucesso) {
        print("Não foi possível restaurar a sessão do Google automaticamente.");
      }
    });
  }

  // Carrega os caminhos salvos anteriormente
  Future<void> _loadPaths() async {
    final prefs = await SharedPreferences.getInstance();
    String? lastSyncIso = prefs.getString('last_sync_date');

    setState(() {
      _downloadPath = prefs.getString('download_path') ?? "";
      _backupPath = prefs.getString('backup_path') ?? "";
      // Formata a data para exibição
      _localSyncDateDisplay = _formatDate(lastSyncIso);
    });
  }

  // Função para escolher pastas (Download ou Backup)
  Future<void> _pickFolder(bool isDownload, {String? initialPath}) async {
    String? resolvedInitialDir;

    // 1. Se já existe um caminho salvo, tentamos usar ele primeiro
    if (initialPath != null &&
        initialPath.isNotEmpty &&
        initialPath.startsWith('/')) {
      if (Directory(initialPath).existsSync()) {
        resolvedInitialDir = initialPath;
      }
    }

    // 2. SE ESTIVER VAZIO (Padrão), forçamos o Android a ir para lugares diferentes
    if (resolvedInitialDir == null) {
      if (isDownload) {
        // Força a pasta de Downloads padrão do Android
        resolvedInitialDir = "/storage/emulated/0/Download";
      } else {
        // Força a raiz do armazenamento interno para o Backup
        resolvedInitialDir = "/storage/emulated/0";
      }

      // Verificação extra de segurança: se o caminho forçado não existir, volta para null
      if (!Directory(resolvedInitialDir).existsSync()) {
        resolvedInitialDir = null;
      }
    }

    // 3. Abre o seletor
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      initialDirectory: resolvedInitialDir,
    );

    if (selectedDirectory != null) {
      try {
        final testFile = File(p.join(selectedDirectory, '.test_write'));
        await testFile.writeAsString('test');
        await testFile.delete();

        final prefs = await SharedPreferences.getInstance();
        if (isDownload) {
          await prefs.setString('download_path', selectedDirectory);
        } else {
          await prefs.setString('backup_path', selectedDirectory);
        }

        // Atualiza as variáveis locais para refletir na UI imediatamente
        await _loadPaths();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("O Android bloqueou esta pasta. Escolha outra."),
          ),
        );
      }
    }
  }

  // Lógica de Backup: Copia o DB para a pasta de backup com data/hora
  Future<void> _handleBackup() async {
    if (_backupPath == "Não configurado") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Selecione primeiro uma pasta de backup!"),
        ),
      );
      return;
    }

    try {
      final dbDir = await getDatabasesPath();
      final dbPath = p.join(dbDir, 'calibre_drive.db');
      final dbFile = File(dbPath);

      if (await dbFile.exists()) {
        String timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
        String backupName = "calibre_backup_$timestamp.db";
        final destination = p.join(_backupPath, backupName);

        await DatabaseService().closeDatabase();
        await dbFile.copy(destination);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Backup criado: $backupName")));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Erro no backup: $e")));
    }
  }

  // Lógica de Restore: Substitui o DB atual e fecha o app
  Future<void> _handleRestore() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Confirmar Restore?"),
          content: const Text(
            "O banco de dados atual será substituído. O app será fechado para aplicar.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancelar"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                "Restaurar",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirm == true) {
        final dbDir = await getDatabasesPath();
        final dbPath = p.join(dbDir, 'calibre_drive.db');
        await File(result.files.single.path!).copy(dbPath);

        // Fecha o app para reiniciar o banco
        SystemNavigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configurações")),
      body: ListView(
        children: [
          _buildHeader("Armazenamento"),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text("Pasta de Downloads"),
            subtitle: Text(
              _downloadPath.isEmpty
                  ? "Padrão do Sistema (Interno)"
                  : _downloadPath,
              style: TextStyle(
                color: _downloadPath.isEmpty ? Colors.grey : Colors.blueGrey,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Botão para Limpar/Resetar
                if (_downloadPath.isNotEmpty &&
                    _downloadPath != "Padrão do Sistema")
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    onPressed: () async {
                      // 1. Limpa no SharedPreferences
                      await SettingsService.setDownloadPath("");

                      // 2. Atualiza a tela
                      setState(() {
                        _downloadPath = "";
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Caminho redefinido para o padrão."),
                        ),
                      );
                    },
                  ),
                const Icon(Icons.folder_open, color: Colors.blue),
              ],
            ),
            onTap: () => _pickFolder(true, initialPath: _downloadPath),
          ),
          ListTile(
            leading: const Icon(Icons.backup_table),
            title: const Text("Pasta de Backups"),
            subtitle: Text(
              _backupPath.isEmpty || _backupPath == "Padrão do Sistema"
                  ? "Padrão do Sistema (Interno)"
                  : _backupPath,
              style: TextStyle(
                color:
                    (_backupPath.isEmpty || _backupPath == "Padrão do Sistema")
                    ? Colors.grey
                    : Colors.blueGrey,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Só mostra o botão de limpar se não estiver no padrão
                if (_backupPath.isNotEmpty &&
                    _backupPath != "Padrão do Sistema")
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outlined,
                      color: Colors.redAccent,
                    ),
                    onPressed: () async {
                      // 1. Limpa no SharedPreferences
                      await SettingsService.setBackupPath("");

                      // 2. Atualiza a tela
                      setState(() {
                        _backupPath = "";
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Pasta de backup redefinida para o padrão.",
                          ),
                        ),
                      );
                    },
                  ),
                const Icon(Icons.folder_open, color: Colors.blue),
              ],
            ),
            onTap: () => _pickFolder(false, initialPath: _backupPath),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _handleBackup,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text("Backup"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _handleRestore,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text("Restore"),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          _buildHeader("Dados e Sincronia"),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text("Verificar atualização no Drive"),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Local: $_localSyncDateDisplay",
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  "Nuvem: $_driveSyncDateDisplay",
                  style: TextStyle(
                    fontSize: 12,
                    color: _driveSyncDateDisplay == "Clique para verificar"
                        ? Colors.grey
                        : Colors.blue,
                  ),
                ),
              ],
            ),
            onTap: () async {
              if (_googleDriveService.isSignedIn == false) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Acesse a tela inicial para validar sua conta Google.",
                    ),
                  ),
                );
                return;
              }

              // 1. Mostrar feedback visual de que está processando
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) =>
                    const Center(child: CircularProgressIndicator()),
              );

              try {
                final prefs = await SharedPreferences.getInstance();
                final dbFileId = prefs.getString('db_file_id');

                if (dbFileId == null || dbFileId.isEmpty) {
                  Navigator.pop(context); // Fecha o loading
                  _showErrorSnackBar(
                    "ID do banco não encontrado. Sincronize na Home primeiro.",
                  );
                  return;
                }

                final driveFile = await _googleDriveService.getFileMetadata(
                  dbFileId,
                );

                // 3. Pegar a data da última sincronização salva no app
                String? lastSync = await SettingsService.getLastSync();

                // Fechar o carregamento
                if (context.mounted) Navigator.pop(context);

                if (driveFile != null && driveFile.modifiedTime != null) {
                  setState(() {
                    _driveSyncDateDisplay = _formatDate(
                      driveFile.modifiedTime!.toIso8601String(),
                    );
                  });

                  DateTime driveDate = driveFile.modifiedTime!;

                  if (lastSync == null ||
                      driveDate.isAfter(DateTime.parse(lastSync))) {
                    // 4. Existe uma versão mais nova!
                    _showUpdateDialog(driveDate, lastSync);
                  } else {
                    _showSuccessSnackBar(
                      "O banco de dados já está na versão mais recente.",
                    );
                  }
                } else {
                  _showErrorSnackBar(
                    "Não foi possível verificar o arquivo no Google Drive.",
                  );
                }
              } catch (e) {
                if (mounted) Navigator.pop(context);
                _showErrorSnackBar("Erro na verificação: $e");
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showUpdateDialog(DateTime driveDate, String? localDateStr) {
    final String formattedDrive = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(driveDate.toLocal());
    // Formata a data local que já temos
    final String formattedLocal = _formatDate(localDateStr);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Atualização Disponível"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Uma nova versão foi encontrada no Drive.\n"),
            Text(
              "Versão Atual (Local): $formattedLocal",
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              "Nova Versão (Nuvem): $formattedDrive",
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const Text("\nDeseja baixar e atualizar agora?"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("AGORA NÃO"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _atualizarBancoDados(driveDate);
            },
            child: const Text("ATUALIZAR"),
          ),
        ],
      ),
    );
  }

  // Esta é a função que realmente faz o trabalho de baixar
  Future<void> _atualizarBancoDados(DateTime driveDate) async {
    // Mostra um progresso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. Chame sua função existente de download do metadata.db
      final dbFileId = await SettingsService.getDbFileId();

      if (dbFileId != null) {
        final file = await _googleDriveService.downloadMetadata(dbFileId);

        if (file != null) {
          // 2. Localiza o caminho do banco de dados local
          //final dbDir = await getDatabasesPath();
          //final dbPath = p.join(dbDir, 'calibre_drive.db');

          // 3. Grava os bytes no arquivo físico
          //final file = File(dbPath);
          //await file.writeAsBytes(bytes);

          // 4. Salva a data da nova versão
          await SettingsService.setLastSync(driveDate.toIso8601String());

          await _loadPaths(); // Recarrega as datas na tela

          if (mounted) {
            Navigator.pop(context); // Fecha o progresso
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Banco de dados atualizado com sucesso!"),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "ID do banco não encontrado. Sincronize na tela inicial primeiro.",
              ),
            ),
          );
        }
      } else {
        // Tratar caso o ID seja nulo
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ID do banco não encontrado.")),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Fecha o progresso
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao atualizar: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return "N/A";
    try {
      DateTime dt = DateTime.parse(isoDate).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (e) {
      return "Erro na data";
    }
  }
}
