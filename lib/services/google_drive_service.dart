import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'dart:io'; // Necessário para manipular arquivos
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  drive.DriveApi? _driveApi;
  GoogleSignInAccount? _currentUser;

  // Escopo estrito: Apenas leitura de arquivos
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.readonly', // Ler metadados
      'https://www.googleapis.com/auth/drive.file', // Baixar e manipular arquivos
    ],
  );

  //GoogleSignInAccount? _currentUser;

  Future<void> initializeWithHeaders(Map<String, String> authHeaders) async {
    final client = GoogleAuthClient(authHeaders);
    _driveApi = drive.DriveApi(client);
  }

  // Getter para verificar se está logado
  bool get isSignedIn => _currentUser != null;

  // 1. Função de Login
  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser != null) {
        // Autentica o cliente HTTP automaticamente com as credenciais do Google
        final httpClient = await _googleSignIn.authenticatedClient();
        if (httpClient != null) {
          _driveApi = drive.DriveApi(httpClient);
          return true;
        }
      }
      return false;
    } catch (e) {
      print("Erro no Google SignIn: $e");
      return false;
    }
  }

  // 2. Busca o ID da pasta raiz da biblioteca Calibre
  // O usuário geralmente nomeia como "Biblioteca do Calibre" ou similar
  Future<String?> findCalibreFolderId(String folderName) async {
    if (_driveApi == null) {
      print("!!!!! ALERTA: A API DO DRIVE ESTÁ NULA NO SERVICE !!!!!");
      return null;
    }

    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final list = await _driveApi!.files.list(q: query, spaces: 'drive');

    return list.files?.isNotEmpty == true ? list.files!.first.id : null;
  }

  Future<void> scanEverything(String rootFolderId, dbService) async {
    // 1. Mapear pastas: ID da pasta -> ID do Calibre
    // Buscamos apenas pastas que tenham o (ID) no nome
    Map<String, int> folderToCalibreId = {};
    String? folderToken;

    do {
      final folders = await _driveApi!.files.list(
        q: "mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        pageToken: folderToken,
      );

      for (var f in folders.files ?? []) {
        final match = RegExp(r'\((\d+)\)').firstMatch(f.name!);
        if (match != null) {
          folderToCalibreId[f.id!] = int.parse(match.group(1)!);
        }
      }
      folderToken = folders.nextPageToken;
    } while (folderToken != null);

    // 2. Agora buscamos os arquivos (Capas e Livros)
    List<Map<String, String>> coverList = [];
    List<Map<String, dynamic>> fileList = [];
    String? fileToken;

    // 2. Agora buscamos os arquivos (Capas e Livros) em qualquer lugar do Drive
    do {
      final result = await _driveApi!.files.list(
        // Buscamos apenas arquivos (não pastas) que não estão na lixeira
        q: "trashed = false and mimeType != 'application/vnd.google-apps.folder'",
        spaces: 'drive',
        pageToken: fileToken,
        pageSize: 1000,
        $fields: "nextPageToken, files(id, name, parents)",
      );

      if (result.files != null) {
        for (var file in result.files!) {
          // Se o arquivo não tiver pai, ignoramos
          if (file.parents == null || file.parents!.isEmpty) continue;

          String parentId = file.parents!.first;

          // Aqui está a mágica: verificamos se o pai deste arquivo
          // é uma das 997 pastas de livros que mapeamos no passo 1
          int? bookId = folderToCalibreId[parentId];

          if (bookId != null) {
            String name = file.name!.toLowerCase();

            if (name == 'cover.jpg') {
              coverList.add({'id': bookId.toString(), 'fileId': file.id!});
            } else if (name.endsWith('.epub')) {
              fileList.add({
                'book_id': bookId,
                'format': 'epub',
                'file_id': file.id!,
              });
            } else if (name.endsWith('.pdf')) {
              fileList.add({
                'book_id': bookId,
                'format': 'pdf',
                'file_id': file.id!,
              });
            }
          }
        }
      }
      fileToken = result.nextPageToken;
    } while (fileToken != null);

    // 3. Salvar no banco
    await dbService.saveCoverCache(coverList);
    await dbService.saveFileCache(fileList);
  }

  Future<drive.File?> getFileMetadata(String fileId) async {
    try {
      // Verificamos se a API foi inicializada antes de usar
      if (_driveApi == null) {
        print("Erro: Google Drive API não inicializada.");
        return null;
      }

      // Buscamos o arquivo de forma segura
      final response = await _driveApi!.files.get(
        fileId,
        $fields: 'id, name, modifiedTime',
      );

      return response as drive.File;
    } catch (e) {
      print("Erro ao buscar metadados: $e");
      return null;
    }
  }

  Future<File?> downloadMetadata(String fileId, {String? customPath}) async {
    if (_driveApi == null) return null;

    try {
      // Se passarmos um caminho, usamos ele.
      // Se não, ele usa o seu padrão atual (getDatabasesPath).
      String savePath;
      if (customPath != null) {
        savePath = customPath;
      } else {
        final dbDir = await getDatabasesPath();
        savePath = p.join(dbDir, 'metadata.db');
      }

      final response =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final List<int> dataStore = [];
      await for (final data in response.stream) {
        dataStore.addAll(data);
      }

      final file = File(savePath);
      await file.writeAsBytes(dataStore);

      return file;
    } catch (e) {
      print("Erro ao baixar metadata: $e");
      return null;
    }
  }

  Future<String?> findFileIdByName(String fileName, String parentId) async {
    if (_driveApi == null) return null;

    // Busca o arquivo pelo nome exato, que não esteja na lixeira e que o pai seja a pasta da biblioteca
    final query =
        "name = '$fileName' and '$parentId' in parents and trashed = false";

    final list = await _driveApi!.files.list(
      q: query,
      $fields: "files(id, name)",
    );

    return list.files?.isNotEmpty == true ? list.files!.first.id : null;
  }

  // Retorna os cabeçalhos de autenticação para as imagens
  Future<Map<String, String>> getAuthHeaders() async {
    final user = _googleSignIn.currentUser;
    if (user == null) {
      print("Usuário não está logado!");
      return {}; // Retorna vazio em vez de dar erro
    }
    return await user.authHeaders;
  }

  // Constrói a URL direta de visualização do Google Drive
  String getImageUrl(String fileId) {
    return "https://www.googleapis.com/drive/v3/files/$fileId?alt=media";
  }

  // Adicione este método ao seu GoogleDriveService

  Future<drive.File?> getFileMetadataByName(
    String fileName,
    String parentId,
  ) async {
    if (_driveApi == null) return null;

    final query =
        "name = '$fileName' and '$parentId' in parents and trashed = false";

    // Pedimos especificamente id, name e modifiedTime
    final list = await _driveApi!.files.list(
      q: query,
      $fields: "files(id, name, modifiedTime)",
    );

    return list.files?.isNotEmpty == true ? list.files!.first : null;
  }

  Future<File?> downloadBookFile(
    String fileId,
    String fileName, {
    String? customPath,
  }) async {
    if (_driveApi == null) {
      print("!!!!! ALERTA: A API DO DRIVE ESTÁ NULA NO SERVICE !!!!!");
      return null;
    }

    try {
      //final directory = await getApplicationDocumentsDirectory();
      //final file = File("${directory.path}/$fileName");

      // 1. Define o diretório base
      Directory directory;
      if (customPath != null && customPath.isNotEmpty) {
        directory = Directory(customPath);
      } else {
        // Se não vier caminho customizado, mantém o seu padrão original
        directory = await getApplicationDocumentsDirectory();
      }

      // Garante que a pasta existe
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final file = File("${directory.path}/$fileName");

      print("!!!!! ESTOU DENTRO DO SERVICE AGORA !!!!!");
      print("Tentando baixar ID: $fileId");

      // Mudança importante: Pegamos a resposta como 'dynamic' para evitar erro de cast
      dynamic response = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );

      List<int> bytes = [];

      // Verificamos se a resposta contém o Stream esperado
      if (response is drive.Media) {
        await for (var data in response.stream) {
          bytes.addAll(data);
        }
      } else {
        print("Resposta inesperada do Drive: ${response.runtimeType}");
        return null;
      }

      if (bytes.isEmpty) {
        print("Alerta: Recebidos 0 bytes do arquivo.");
        return null;
      }

      await file.writeAsBytes(bytes, flush: true);
      print("Download concluído: ${bytes.length} bytes salvos.");
      return file;
    } catch (e) {
      // ESTE PRINT É O MAIS IMPORTANTE AGORA
      print("ERRO REAL NA API DRIVE: $e");
      return null;
    }
  }

  Future<bool> restoreSession() async {
    try {
      // Tenta pegar o usuário que já estava logado antes
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        final httpClient = await _googleSignIn.authenticatedClient();
        if (httpClient != null) {
          _driveApi = drive.DriveApi(httpClient);
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}
