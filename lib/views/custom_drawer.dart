import 'package:calibre_drive/services/database_service.dart';
import 'package:calibre_drive/services/google_drive_service.dart';
import 'package:calibre_drive/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_page.dart';
import 'file_manager_page.dart';

class CustomDrawer extends StatefulWidget {
  final VoidCallback? onSyncComplete;
  const CustomDrawer({super.key, this.onSyncComplete});

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  // --- VARIÁVEIS DO EASTER EGG ---
  int _boltClicks = 0;
  DateTime? _lastBoltClick;

  String _appVersion = "";
  String _appName = "";

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _appName = info.appName;
      _appVersion = info.version; // Puxa o 1.0.0
      // info.buildNumber puxa o número após o + (ex: 1)
    });
  }

  void _handleBoltClick() {
    final now = DateTime.now();
    if (_lastBoltClick != null &&
        now.difference(_lastBoltClick!).inSeconds > 2) {
      _boltClicks = 0;
    }
    _boltClicks++;
    _lastBoltClick = now;

    if (_boltClicks == 5) {
      _boltClicks = 0;
      _showEasterEggDialog();
    }
  }

  void _showEasterEggDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.amber),
            const SizedBox(width: 10),
            Text(_appName.toUpperCase()), // Nome que você pegou no PackageInfo
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Informações Técnicas:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text("Versão: $_appVersion"),
            const Text("Desenvolvedor: Luciano Sotello"),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                "⚡ Projeto Eletrificado ⚡",
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.amber,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Fechar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Cabeçalho estilizado
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              color: Colors.blue,
              image: DecorationImage(
                image: NetworkImage(
                  "https://www.gstatic.com/images/branding/product/2x/drive_2020q4_48dp.png",
                ), // Apenas um detalhe visual
                alignment: Alignment.bottomRight,
                opacity: 0.1,
              ),
            ),
            accountName: Padding(
              padding: const EdgeInsets.only(
                top: 25.0,
              ), // Cria o espaço acima do texto
              child: const Text(
                "Calibre Drive",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            accountEmail: const Text("Gerenciador de Biblioteca"),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.book, color: Colors.blue, size: 40),
            ),
          ),

          // Menu: Configurações
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text("Configurações"),
            onTap: () {
              Navigator.pop(context); // Fecha o drawer
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),

          // Menu: Gerenciar Downloads
          ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: const Text("Gerenciar Arquivos"),
            subtitle: const Text("Excluir livros baixados"),
            onTap: () async {
              Navigator.pop(context);

              // MUDANÇA AQUI: Use o caminho "Efetivo" (Customizado ou Padrão)
              final path = await SettingsService.getEffectiveDownloadPath();

              // Remova a verificação de path.isNotEmpty se você quer que o padrão sempre funcione
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FileManagerPage(directoryPath: path),
                  ),
                );
              }
            },
          ),

          const Divider(),

          // Menu: Sincronização rápida (Opcional, mas útil)
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text("Sincronizar Agora"),
            onTap: () async {
              // 1. Fecha o Drawer IMEDIATAMENTE
              Navigator.of(context).pop();

              // 2. Mostra o Loading e guarda o contexto dele
              BuildContext? dialogContext;

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) {
                  dialogContext =
                      ctx; // Captura o contexto específico do Dialog
                  return const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text("Sincronizando biblioteca..."),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );

              // Função interna para fechar o dialog com segurança
              void closeLoading() {
                if (dialogContext != null && dialogContext!.mounted) {
                  Navigator.of(dialogContext!).pop();
                }
              }

              try {
                final googleService = GoogleDriveService();
                // ... lógica de restore session e checks ...

                final prefs = await SharedPreferences.getInstance();
                final fileId = prefs.getString('db_file_id');

                if (fileId == null) {
                  closeLoading(); // FECHA AQUI
                  _showSnackBar(context, "ID do banco não encontrado.");
                  return;
                }

                final driveFile = await googleService.getFileMetadata(fileId);

                if (driveFile != null && driveFile.modifiedTime != null) {
                  // CORREÇÃO: Definimos o caminho interno fixo para o banco
                  final dbPath = await SettingsService.getDatabaseLocalPath();

                  // Fazemos o download forçando esse caminho
                  final file = await googleService.downloadMetadata(
                    fileId,
                    customPath:
                        dbPath, // Garanta que seu serviço aceite esse parâmetro
                  );

                  if (file != null) {
                    await DatabaseService().openCalibreDatabase(file.path);
                    await SettingsService.setLastSync(
                      driveFile.modifiedTime!.toUtc().toIso8601String(),
                    );

                    closeLoading(); // FECHA AQUI NO SUCESSO

                    if (context.mounted) {
                      _showSnackBar(
                        context,
                        "Biblioteca atualizada!",
                        isError: false,
                      );

                      // CHAMA A ATUALIZAÇÃO DA HOME AQUI:
                      widget.onSyncComplete?.call();
                    }
                  } else {
                    closeLoading();
                    _showSnackBar(context, "Falha no download.");
                  }
                } else {
                  closeLoading();
                  _showSnackBar(context, "Erro nos metadados.");
                }
              } catch (e) {
                closeLoading(); // FECHA AQUI NO ERRO
                _showSnackBar(context, "Erro na sincronia: $e");
              }
            },
          ),

          const Spacer(), // Empurra o rodapé para baixo
          // Rodapé com versão
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "$_appName v$_appVersion", // Ex: Calibre Drive v1.0.0
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                GestureDetector(
                  onTap: _handleBoltClick,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.bolt, color: Colors.amber, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = true,
  }) {
    // Se o widget que chamou essa função não está mais na tela, não faz nada
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}
