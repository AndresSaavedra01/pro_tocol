import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:pro_tocol/model/entities/FileNode.dart';

class SFTPService {
  final SSHClient _client;
  SftpClient? _sftpInternal;

  SFTPService(this._client);

  Future<SftpClient> _ensureSftp() async {
    _sftpInternal ??= await _client.sftp();
    return _sftpInternal!;
  }

  Future<List<FileNode>> listDirectory(String directoryPath) async {
    final sftp = await _ensureSftp();
    final List<SftpName> items = await sftp.listdir(directoryPath);
    return items.map((item) {
      final String fullPath = directoryPath.endsWith('/')
          ? '$directoryPath${item.filename}'
          : '$directoryPath/${item.filename}';

      return FileNode(
        name: item.filename,
        path: fullPath,
        type: FileNode.parseType(item.filename, item.attr.isDirectory),
        sizeInBytes: item.attr.size ?? 0,
        permissions: item.attr.mode?.toString() ?? '---',
        lastModified: DateTime.fromMillisecondsSinceEpoch((item.attr.modifyTime ?? 0) * 1000),
      );
    }).where((node) => node.name != '.' && node.name != '..').toList();
  }

  // --- NUEVAS FUNCIONES TURBO ---

  Future<void> createDirectory(String path) async {
    final sftp = await _ensureSftp();
    await sftp.mkdir(path);
  }

  Future<void> rename(String oldPath, String newPath) async {
    final sftp = await _ensureSftp();
    await sftp.rename(oldPath, newPath);
  }

  Future<void> remove(FileNode node) async {
    final sftp = await _ensureSftp();
    if (node.isDirectory) {
      await sftp.rmdir(node.path);
    } else {
      await sftp.remove(node.path);
    }
  }

  Future<void> uploadFile(String localPath, String remotePath) async {
    final sftp = await _ensureSftp();
    final file = File(localPath);
    final remoteFile = await sftp.open(remotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
    await remoteFile.write(file.openRead().cast<Uint8List>());
  }

  Future<Uint8List> downloadFile(String remotePath) async {
    final sftp = await _ensureSftp();
    final file = await sftp.open(remotePath);
    final content = await file.read().fold<List<int>>([], (p, e) => p..addAll(e));
    return Uint8List.fromList(content);
  }

  // En SFTPService.dart
  Future<void> createEmptyFile(String path) async {
    final sftp = await _ensureSftp();
    // Abrimos el archivo en modo creación y lo cerramos inmediatamente
    final file = await sftp.open(path, mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
    await file.close();
  }
}