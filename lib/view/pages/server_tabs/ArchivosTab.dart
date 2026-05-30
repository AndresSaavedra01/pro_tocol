import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_tocol/model/entities/FileNode.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import '../../theme/AppColors.dart';
import 'package:file_picker/file_picker.dart' hide FileType;

class ArchivosTab extends StatefulWidget {
  final Server? activeServer;

  const ArchivosTab({super.key, required this.activeServer});

  @override
  State<ArchivosTab> createState() => _ArchivosTabState();
}

class _ArchivosTabState extends State<ArchivosTab> {
  String currentPath = "/";
  List<FileNode> currentFiles = [];
  final TextEditingController _pathController = TextEditingController(text: "/");
  bool _isLoading = false;

  // Estado para Copiar/Pegar
  FileNode? _clipboardNode;
  bool _isCut = false;

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  @override
  void didUpdateWidget(covariant ArchivosTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeServer == null && widget.activeServer != null) {
      _refreshFiles();
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  // Función auxiliar para normalizar rutas y evitar el doble "/" (ej: //carpeta)
  String _normalizePath(String path) {
    return path.replaceAll(RegExp(r'/{2,}'), '/');
  }

  // --- NAVEGACIÓN Y CARGA DE DATOS ---

  void _changePath(String newPath) {
    if (newPath.isEmpty) newPath = "/";
    if (!newPath.startsWith("/")) newPath = "/$newPath"; // Asegurar ruta absoluta

    setState(() {
      currentPath = _normalizePath(newPath);
      _pathController.text = currentPath; // Sincroniza la barra de navegación
    });
    _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    if (widget.activeServer?.sshService.sftp == null) return;
    setState(() => _isLoading = true);
    try {
      final files = await widget.activeServer!.sshService.sftp!.listDirectory(currentPath);
      if (mounted) setState(() { currentFiles = files; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double size = bytes.toDouble();
    while (size > 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return "${size.toStringAsFixed(1)} ${suffixes[i]}";
  }

  // --- LÓGICA DE ARCHIVOS (SUBIR, BAJAR, PEGAR) ---

  Future<void> _handleUpload() async {
    FilePickerResult? result = await FilePicker.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => _isLoading = true);
      final localPath = result.files.single.path!;
      final fileName = result.files.single.name;
      
      try {
        final remotePath = _normalizePath("$currentPath/$fileName");
        await widget.activeServer!.sshService.sftp!.uploadFile(localPath, remotePath);
        await _refreshFiles();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al subir archivo: $e"), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleUploadFolder() async {
    String? directoryPath = await FilePicker.getDirectoryPath();
    if (directoryPath != null) {
      setState(() => _isLoading = true);
      try {
        final dir = Directory(directoryPath);
        final folderName = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;

        final remoteFolder = _normalizePath("$currentPath/$folderName");
        await widget.activeServer!.sshService.sftp!.createDirectory(remoteFolder);

        final files = dir.listSync().whereType<File>();
        for (var file in files) {
          final fileName = file.uri.pathSegments.last;
          final remoteFilePath = _normalizePath("$remoteFolder/$fileName");
          await widget.activeServer!.sshService.sftp!.uploadFile(file.path, remoteFilePath);
        }
        await _refreshFiles();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al subir carpeta: $e"), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDownload(FileNode node) async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.activeServer!.sshService.sftp!.downloadFile(node.path);
      final tempDir = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final file = File("${tempDir.path}/${node.name}");
      await file.writeAsBytes(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Descargado en:\n${file.path}")));
      }
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error descargando: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pasteFile() async {
    if (_clipboardNode == null) return;
    setState(() => _isLoading = true);
    try {
      final newPath = _normalizePath("$currentPath/${_clipboardNode!.name}");
      await widget.activeServer!.sshService.sftp!.rename(_clipboardNode!.path, newPath);
      setState(() { _clipboardNode = null; _isCut = false; });
      await _refreshFiles();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al pegar: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nueva Carpeta"),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: "Nombre de la carpeta")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          TextButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  Navigator.pop(context);
                  setState(() => _isLoading = true);
                  
                  try {
                    final remotePath = _normalizePath("$currentPath/${controller.text}");
                    await widget.activeServer!.sshService.sftp!.createDirectory(remotePath);
                    await _refreshFiles();
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al crear carpeta: $e"), backgroundColor: Colors.red));
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                }
              },
              child: const Text("Crear")
          ),
        ],
      ),
    );
  }

  void _showCreateFileDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nuevo Archivo"),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: "ejemplo.txt")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          TextButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  Navigator.pop(context);
                  setState(() => _isLoading = true);
                  
                  try {
                    final remotePath = _normalizePath("$currentPath/${controller.text}");
                    await widget.activeServer!.sshService.sftp!.createEmptyFile(remotePath);
                    await _refreshFiles();
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al crear archivo: $e"), backgroundColor: Colors.red));
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                }
              },
              child: const Text("Crear")
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(FileNode node) {
    final controller = TextEditingController(text: node.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Renombrar"),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          TextButton(
              onPressed: () async {
                if (controller.text.isNotEmpty && controller.text != node.name) {
                  Navigator.pop(context);
                  setState(() => _isLoading = true);

                  try {
                    final String parentPath = node.path.substring(0, node.path.lastIndexOf('/'));
                    final String newPath = _normalizePath(parentPath.isEmpty ? "/${controller.text}" : "$parentPath/${controller.text}");

                    await widget.activeServer!.sshService.sftp!.rename(node.path, newPath);
                    await _refreshFiles();
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al renombrar: $e"), backgroundColor: Colors.red));
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                }
              },
              child: const Text("Guardar")
          ),
        ],
      ),
    );
  }

  // --- MENÚS DESPLEGABLES (BOTTOM SHEETS) ---

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Transferencias y Creacion", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted)),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.blueAccent),
              title: const Text('Subir Archivo Local', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(context); _handleUpload(); },
            ),
            ListTile(
              leading: const Icon(Icons.drive_folder_upload, color: Colors.green),
              title: const Text('Subir Carpeta Local', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(context); _handleUploadFolder(); },
            ),
            const Divider(color: AppColors.border),
            ListTile(
              leading: const Icon(Icons.note_add, color: AppColors.textPrimary),
              title: const Text('Crear Archivo Vacio', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(context); _showCreateFileDialog(); },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder, color: AppColors.textPrimary),
              title: const Text('Crear Carpeta', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(context); _showCreateFolderDialog(); },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text("Para descargar, manten presionado un archivo de la lista.", style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontStyle: FontStyle.italic)),
            )
          ],
        ),
      ),
    );
  }

  void _showFileOptions(FileNode node) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted)),
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.blueAccent),
              title: const Text('Descargar a mi dispositivo', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(context); _handleDownload(node); },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: AppColors.textPrimary),
              title: const Text('Copiar / Mover', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                setState(() { _clipboardNode = node; _isCut = true; });
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.textPrimary),
              title: const Text('Renombrar', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () { Navigator.pop(context); _showRenameDialog(node); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Eliminar', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                setState(() => _isLoading = true);
                try {
                  await widget.activeServer!.sshService.sftp!.remove(node);
                  await _refreshFiles();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red));
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildPathBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, color: AppColors.textPrimary),
            onPressed: currentPath == "/" ? null : () {
              List<String> parts = currentPath.split('/')..removeWhere((p) => p.isEmpty);
              if (parts.isNotEmpty) {
                parts.removeLast();
                _changePath(parts.isEmpty ? "/" : "/${parts.join('/')}");
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _pathController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                  hintText: 'Ej: /var/www/html',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (value) => _changePath(value.trim()),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textMuted),
            onPressed: () => _changePath(_pathController.text.trim()),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(FileNode node) {
    final isDir = node.isDirectory;
    IconData icon = Icons.insert_drive_file;
    Color color = AppColors.textMuted;

    // Asignación de colores e íconos
    if (isDir) {
      icon = Icons.folder;
      color = AppColors.fileDir;
    } else if (node.type == FileType.txt || node.type == FileType.markdown) {
      icon = Icons.description;
      color = AppColors.fileTxt;
    } else if (node.type == FileType.image) {
      icon = Icons.image;
      color = AppColors.fileImg;
    } else if (node.type == FileType.config) {
      icon = Icons.settings;
      color = AppColors.fileCfg;
    }

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      subtitle: Text("${node.permissions} • ${_formatSize(node.sizeInBytes)}",
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),

      onTap: () {
        if (isDir) _changePath(node.path);
      },
      onLongPress: () => _showFileOptions(node),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0), 
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Solo muestra el botón Pegar si copiaste algo antes
            if (_clipboardNode != null) ...[
              FloatingActionButton.small(
                heroTag: "paste",
                backgroundColor: Colors.orange,
                onPressed: _pasteFile,
                child: const Icon(Icons.paste, color: Colors.white),
              ),
              const SizedBox(height: 12),
            ],

            // Botón de Transferencias unificado (Subir/Crear)
            FloatingActionButton(
              heroTag: "transfer_menu",
              backgroundColor: AppColors.primary,
              onPressed: _showAddMenu,
              child: const Icon(Icons.dashboard_customize_outlined, color: Colors.white),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildPathBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _refreshFiles,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 160), // Previene que ambos FABs tapen el final de la lista
                itemCount: currentFiles.length,
                itemBuilder: (context, i) => _buildFileItem(currentFiles[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

}