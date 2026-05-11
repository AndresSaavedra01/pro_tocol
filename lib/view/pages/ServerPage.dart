import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:pro_tocol/controller/ServerConnectionController.dart';
import 'package:pro_tocol/injection.dart';
import 'package:pro_tocol/view/pages/server_tabs/AppsManagerTab.dart';
import 'package:pro_tocol/view/pages/server_tabs/ArchivosTab.dart';
import 'package:pro_tocol/view/pages/server_tabs/MonitorTab.dart';
import 'package:pro_tocol/view/pages/server_tabs/SeguridadTab.dart';
import 'package:pro_tocol/view/pages/server_tabs/TerminalTab.dart';
import 'package:pro_tocol/view/pages/server_tabs/TemplatesTab.dart';
import 'package:xterm/xterm.dart';
import 'package:pro_tocol/view/pages/server_tabs/ChatIaTab.dart';

import 'package:pro_tocol/model/entities/Server.dart';
import '../../model/entities/DataBaseEntities.dart';
import '../theme/AppColors.dart';


class ServerPage extends StatefulWidget {
  final ServerConfig serverConfig;
  final bool isTemporarySession;

  const ServerPage({
    super.key,
    required this.serverConfig,
    this.isTemporarySession = false,
  });
  @override
  State<ServerPage> createState() => _ServerPageState();
  ServerConnectionController get _connectionController => getIt<ServerConnectionController>();
}

class _ServerPageState extends State<ServerPage> {
  late final Terminal terminal;
  Server? _activeServer;
  void _showChatModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, 
      barrierColor: Colors.black.withOpacity(0.6), 
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.72,
            decoration: const BoxDecoration(
              color: AppColors.surface, 
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 20,
                  offset: Offset(0, -5),
                )
              ]
            ),
            child: Column(
              children: [
                // Barra decorativa mejorada
                Container(
                  margin: const EdgeInsets.only(top: 15, bottom: 8),
                  height: 6,
                  width: 50,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                // Título más limpio
                const Text(
                  "Asistente Pro-Tocol IA",
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                // Divisor más sutil
                const Divider(color: Colors.white10, height: 1),
                const Expanded(
                  child: ChatIaTab(), 
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  @override
  void initState() {
    super.initState();
    terminal = getIt<Terminal>();
    _connectToServerController();
  }

  Future<void> _connectToServerController() async {
    try {
      _activeServer = widget._connectionController.getActiveServer(widget.serverConfig.id);

      if (mounted) setState(() {});

      // ARREGLO: Forzar un tamaño mínimo al iniciar para que no sea 0x0
      final session = await _activeServer!.sshService.createTerminal(
        width: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
        height: terminal.viewHeight > 0 ? terminal.viewHeight : 24,
      );

      // ARREGLO: Sincronización del tamaño cuando la pantalla de Flutter cambia
      terminal.onResize = (w, h, cw, ch) {
        if (w > 0 && h > 0) {
          session.resizeTerminal(w, h); // <--- CORREGIDO
        }
      };

      _startUniversalSync(session);

      // ARREGLO: Escuchadores únicos (se eliminaron los duplicados)
      session.stdout.listen((d) {
        if (mounted) terminal.write(utf8.decode(d, allowMalformed: true));
      });

      session.stderr.listen((d) {
        if (mounted) terminal.write(utf8.decode(d, allowMalformed: true));
      });

      terminal.onOutput = (input) {
        session.stdin.add(utf8.encode(input));
      };

    } catch (e) {
      if (mounted) terminal.write('\x1B[31mError: $e\x1B[0m\r\n');
    }
  }

  void _startUniversalSync(SSHSession session) {
    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 300), (timer) {
      attempts++;
      if (mounted && terminal.viewWidth > 0) {
        // ARREGLO: Solo se hace resize nativo. Se quitó la llamada a runSingleCommand("stty...")
        session.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
        if (attempts >= 3) timer.cancel();
      }
      if (attempts > 10) timer.cancel();
    });
  }

  String _getDistroIcon(String d) {
    final n = d.toLowerCase();
    if (n.contains('ubuntu')) return '🐧';
    if (n.contains('debian')) return '🦆';
    if (n.contains('arch')) return '🌀';
    if (n.contains('manjaro')) return '🌲';
    if (n.contains('fedora')) return '🛡️';
    if (n.contains('rhel') || n.contains('red hat')) return '🔥';
    return '🐧';
  }

  @override
  Widget build(BuildContext context) {
    final connStr = "${widget.serverConfig.username}@${widget.serverConfig.host}";
    final distroName = _activeServer?.distroName ?? 'Linux';
    final pkgManager = _activeServer?.packageManager ?? 'unknown';
    final distroIcon = _getDistroIcon(distroName);

    return DefaultTabController(
      length: widget.isTemporarySession ? 1 : 6,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          toolbarHeight: widget.isTemporarySession ? kToolbarHeight : 90,
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.isTemporarySession ? 'Sesión Temporal' : widget.serverConfig.host,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                  connStr,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)
              ),
              if (!widget.isTemporarySession) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(distroIcon, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              distroName,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)
                          ),
                          Text(
                              'Pkg: $pkgManager',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 9)
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          bottom: widget.isTemporarySession
              ? null
              : const TabBar(
            isScrollable: true,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'Monitor'),
              Tab(text: 'Terminal'),
              Tab(text: 'Archivos'),
              Tab(text: 'Apps'),
              Tab(text: 'Templates'),
              Tab(text: 'Seguridad'),
            ],
          ),
        ),
        body: widget.isTemporarySession
            ? TerminalTab(terminal: terminal)
            : TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            MonitorTab(activeServer: _activeServer),
            TerminalTab(terminal: terminal),
            ArchivosTab(activeServer: _activeServer),
            AppsManagerTab(
              serverConfig: widget.serverConfig,
              activeServer: _activeServer,
            ),
            TemplatesTab(
              serverConfig: widget.serverConfig,
              activeServer: _activeServer,
            ),
            SeguridadTab(
              serverConfig: widget.serverConfig,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: AppColors.primary,
          elevation: 8,
          child: const Icon(Icons.auto_awesome, color: Colors.white), // Icono IA
          onPressed: () => _showChatModal(context),
        ),
      ),
    );
  }
}