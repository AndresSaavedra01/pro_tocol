import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pro_tocol/controller/ServerCommandController.dart';
import 'package:pro_tocol/injection.dart';
import 'package:pro_tocol/logic/command_history_manager.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/model/entities/TempSession.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';

class DistroLogsPage extends StatefulWidget {
  final Server? activeServer;
  final TempSession? activeSession;

  const DistroLogsPage({
    super.key,
    this.activeServer,
    this.activeSession,
  });

  @override
  State<DistroLogsPage> createState() => _DistroLogsPageState();
}

class _DistroLogsPageState extends State<DistroLogsPage> {
  ServerCommandController get _commandController => getIt<ServerCommandController>();

  @override
  Widget build(BuildContext context) {
    final history = _commandController.commandHistoryManager.getHistory();
    final distroName = widget.activeServer?.distroName ?? widget.activeSession?.distroName ?? 'Linux';
    final packageManager = widget.activeServer?.packageManager ?? widget.activeSession?.packageManager ?? 'unknown';
    final distroIcon = _getDistroIcon(distroName);
    final hasActiveConnection =
        widget.activeServer != null || widget.activeSession != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Distro & Logs',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear, color: AppColors.error),
            onPressed: () {
              _commandController.commandHistoryManager.clear();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Historial limpiado')),
              );
            },
            tooltip: 'Limpiar historial',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            onPressed: () => setState(() {}),
            tooltip: 'Actualizar historial',
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.background, AppColors.surface.withOpacity(0.1)],
          ),
        ),
        child: hasActiveConnection
            ? Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(distroIcon, style: const TextStyle(fontSize: 28)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    distroName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Package Manager: $packageManager',
                                    style: const TextStyle(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: AppColors.border),
                        const SizedBox(height: 12),
                        const Text(
                          'Command History',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: history.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay comandos en el historial',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: history.length,
                            itemBuilder: (context, index) {
                              final command = history[history.length - 1 - index]; // Más reciente primero
                              return ListTile(
                                title: Text(
                                  command,
                                  style: const TextStyle(color: AppColors.textPrimary),
                                ),
                                trailing: const Icon(Icons.copy, color: AppColors.primary),
                                onTap: () async {
                                  await Clipboard.setData(ClipboardData(text: command));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Comando copiado: $command')),
                                    );
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              )
            : const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.computer_outlined,
                        size: 64, color: AppColors.textMuted),
                    SizedBox(height: 16),
                    Text(
                      'Conecta un servidor para ver su información de distro',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  String _getDistroIcon(String distroName) {
    final normalized = distroName.toLowerCase();
    if (normalized.contains('ubuntu')) return '🐧';
    if (normalized.contains('debian')) return '🦆';
    if (normalized.contains('arch')) return '🌀';
    if (normalized.contains('manjaro')) return '🌲';
    if (normalized.contains('fedora')) return '🛡️';
    if (normalized.contains('rhel') || normalized.contains('red hat')) return '🔥';
    return '🐧';
  }
}
