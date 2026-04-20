import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:io'; // Necessário para manipular arquivos
import 'package:path_provider/path_provider.dart';

class GoogleDriveService {
  // Escopo estrito: Apenas leitura de arquivos
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveReadonlyScope],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;

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
    if (_driveApi == null) return null;

    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final list = await _driveApi!.files.list(q: query, spaces: 'drive');

    return list.files?.isNotEmpty == true ? list.files!.first.id : null;
  }

  // 3. Download do arquivo metadata.db
  Future<List<int>?> downloadMetadataDb(String fileId) async {
    if (_driveApi == null) return null;

    final response =
        await _driveApi!.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as http.Response;

    return response.bodyBytes;
  }

  // Esta função faz a varredura e retorna um Mapa {Caminho: ID_do_Arquivo}
  Future<Map<String, String>> scanFolderForCovers(String calibreRootId) async {
    if (_driveApi == null) return {};

    Map<String, String> folderNames = {};
    Map<String, String?> folderParents = {};
    String? pageToken;

    // 1. Buscamos TODAS as pastas (com paginação)
    do {
      final folderList = await _driveApi!.files.list(
        q: "'$calibreRootId' in parents or mimeType = 'application/vnd.google-apps.folder'",
        $fields: "nextPageToken, files(id, name, parents)",
        pageSize: 1000,
        pageToken: pageToken, // Passa o token da próxima página
      );

      for (var f in folderList.files ?? []) {
        folderNames[f.id!] = f.name!;
        folderParents[f.id!] = f.parents?.first;
      }

      pageToken = folderList.nextPageToken; // Atualiza o token
    } while (pageToken != null); // Repete enquanto houver mais páginas

    // 2. Buscamos todos os cover.jpg (também com paginação se necessário)
    Map<String, String> coverMap = {};
    pageToken = null; // Reseta para a nova busca

    do {
      final fileList = await _driveApi!.files.list(
        q: "name = 'cover.jpg' and trashed = false",
        $fields: "nextPageToken, files(id, parents)",
        pageSize: 1000,
        pageToken: pageToken,
      );

      for (var file in fileList.files ?? []) {
        if (file.parents != null && file.parents!.isNotEmpty) {
          String bookFolderId = file.parents!.first;
          String? authorFolderId = folderParents[bookFolderId];

          if (authorFolderId != null && authorFolderId != calibreRootId) {
            String authorName = folderNames[authorFolderId] ?? "";
            String bookFolderName = folderNames[bookFolderId] ?? "";

            if (authorName.isNotEmpty && bookFolderName.isNotEmpty) {
              String fullPath = "$authorName/$bookFolderName";
              coverMap[fullPath] = file.id!;
              // Print de debug para você confirmar no console
              print("Mapeando caminho: $fullPath -> ID: ${file.id}");
            }
          }
        }
      }
      pageToken = fileList.nextPageToken;
    } while (pageToken != null);

    return coverMap;
  }

  // Novo: Pega metadados para comparar datas
  Future<drive.File?> getFileMetadata(String fileId) async {
    return await _driveApi!.files.get(fileId, $fields: "id, name, modifiedTime")
        as drive.File;
  }

  Future<File?> downloadMetadata(String fileId) async {
    if (_driveApi == null) return null;

    try {
      // 1. Pega a pasta de documentos do celular
      final directory = await getApplicationDocumentsDirectory();
      final savePath = "${directory.path}/metadata.db";

      // 2. Faz a requisição de download para o Google
      final response =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      // 3. Converte o stream de dados em um arquivo físico
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
}
