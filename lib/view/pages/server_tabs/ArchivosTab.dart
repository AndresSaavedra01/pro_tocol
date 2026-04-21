
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pro_tocol/model/entities/FileNode.dart';
import 'package:pro_tocol/model/entities/Server.dart';

import '../../theme/AppColors.dart';

class ArchivosTab extends StatefulWidget {
  final Server? activeServer;

  const ArchivosTab({super.key, required this.activeServer});

  @override
  State<ArchivosTab> createState() => _ArchivosTabState();
}

class _ArchivosTabState extends State<ArchivosTab> {
  String currentPath = "/";
  List<FileNode> currentFiles = [];
  bool _isLoadingFiles = false;

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

  Future<void> _refreshFiles() async {
    if (widget.activeServer?.sshService.sftp == null) return;
    setState(() => _isLoadingFiles = true);
    try {
      final files = await widget.activeServer!.sshService.sftp!.listDirectory(currentPath);
      if (mounted) setState(() { currentFiles = files; _isLoadingFiles = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFiles = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error SFTP: $e"), backgroundColor: AppColors.error));
      }
    }
  }

  void _goBack() {
    if (currentPath == "/" || currentPath == "") return;
    List<String> parts = currentPath.split('/');
    if (parts.last.isEmpty) parts.removeLast();
    if (parts.isNotEmpty) parts.removeLast();
    String newPath = parts.join('/');
    if (newPath.isEmpty) newPath = "/";
    setState(() => currentPath = newPath);
    _refreshFiles();
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const s = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${s[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: AppColors.surface,
          child: Row(
            children: [
              if (currentPath != "/")
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward, color: AppColors.primary, size: 20),
                    onPressed: _goBack, tooltip: "Subir un nivel", padding: const EdgeInsets.all(8), constraints: const BoxConstraints(),
                  ),
                ),
              const Icon(Icons.folder_open, color: AppColors.textMuted, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(currentPath, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
              if (_isLoadingFiles)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshFiles,
            child: ListView.builder(
              itemCount: currentFiles.length,
              itemBuilder: (_, i) => _buildFileNodeItem(currentFiles[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileNodeItem(FileNode node) {
    final isDir = node.isDirectory;
    IconData icon = Icons.insert_drive_file;
    Color color = AppColors.textMuted;

    if (isDir) { icon = Icons.folder; color = AppColors.fileDir; }
    else if (node.type == FileType.txt || node.type == FileType.markdown) { icon = Icons.description; color = AppColors.fileTxt; }
    else if (node.type == FileType.image) { icon = Icons.image; color = AppColors.fileImg; }
    else if (node.type == FileType.config) { icon = Icons.settings; color = AppColors.fileCfg; }

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(node.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      subtitle: Text("${node.permissions} • ${_formatSize(node.sizeInBytes)}", style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      trailing: isDir ? const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20) : null,
      onTap: () {
        if (node.isDirectory) {
          if (node.name == ".") return;
          setState(() => currentPath = node.path);
          _refreshFiles();
        }
      },
    );
  }
}