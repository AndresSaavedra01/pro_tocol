import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pro_tocol/logic/command_history_manager.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';

class DistroLogsPage extends StatefulWidget {
  final CommandHistoryManager commandHistoryManager;

  const DistroLogsPage({super.key, required this.commandHistoryManager});

  @override
  State<DistroLogsPage> createState() => _DistroLogsPageState();
}

class _DistroLogsPageState extends State<DistroLogsPage> {
  @override
  Widget build(BuildContext context) {
    final history = widget.commandHistoryManager.getHistory();

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
              widget.commandHistoryManager.clear();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Historial limpiado')),
              );
            },
            tooltip: 'Limpiar historial',
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
    );
  }
}