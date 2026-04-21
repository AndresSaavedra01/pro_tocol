import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:pro_tocol/view/pages/server_tabs/AppsManagerTab.dart';
import 'package:pro_tocol/view/pages/server_tabs/ArchivosTab.dart';
import 'package:pro_tocol/view/pages/server_tabs/MonitorTab.dart';
import 'package:pro_tocol/view/pages/server_tabs/TerminalTab.dart';
import 'package:xterm/xterm.dart';

import 'package:pro_tocol/controller/ServerController.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import '../../model/entities/DataBaseEntities.dart';
import '../theme/AppColors.dart';


class ServerPage extends StatefulWidget {
  final ServerConfig serverConfig;
  final ServerController serverController;
  final bool isTemporarySession;

  const ServerPage({
    super.key,
    required this.serverConfig,
    required this.serverController,
    this.isTemporarySession = false,
  });

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  late final Terminal terminal;
  Server? _activeServer;
  String _currentCommandBuffer = "";

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);
    _connectToServerController();
  }

  Future<void> _connectToServerController() async {
    try {
      _activeServer = widget.serverController.getActiveServer(widget.serverConfig.id);

      // Aseguramos que la UI se entere de que ya tenemos el _activeServer
      if (mounted) setState(() {});

      final session = await _activeServer!.sshService.createTerminal(
        width: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
        height: terminal.viewHeight > 0 ? terminal.viewHeight : 24,
      );

      terminal.onResize = (w, h, cw, ch) {
        if (w > 0 && h > 0) session.resizeTerminal(w, h);
      };

      _startUniversalSync(session);

      session.stdout.listen((d) {
        if (mounted) terminal.write(utf8.decode(d, allowMalformed: true));
      });
      session.stderr.listen((d) {
        if (mounted) terminal.write(utf8.decode(d, allowMalformed: true));
      });
      terminal.onOutput = (input) => _handleTerminalInput(input, session);

      terminal.write('\x1Bc');
      terminal.write('\x1B[32mConexión establecida.\x1B[0m\r\n\n');

    } catch (e) {
      if (mounted) terminal.write('\x1B[31mError: $e\x1B[0m\r\n');
    }
  }

  void _handleTerminalInput(String input, SSHSession session) {
    if (input == '\x1B[A') {
      final cmd = widget.serverController.commandHistoryManager.previous();
      if (cmd != null) _updateCommandBuffer(cmd);
      return;
    } else if (input == '\x1B[B') {
      final cmd = widget.serverController.commandHistoryManager.next();
      if (cmd != null) { _updateCommandBuffer(cmd); } else { _clearCommandBuffer(); }
      return;
    } else if (input == '\r' || input == '\n') {
      if (_currentCommandBuffer.isNotEmpty) {
        session.stdin.add(utf8.encode('$_currentCommandBuffer\n'));
        _currentCommandBuffer = "";
      } else {
        session.stdin.add(utf8.encode(input));
      }
      return;
    } else if (input == '\x7F' || input == '\b') {
      if (_currentCommandBuffer.isNotEmpty) {
        _currentCommandBuffer = _currentCommandBuffer.substring(0, _currentCommandBuffer.length - 1);
        terminal.write('\b \b');
        return;
      }
    } else if (input.length == 1 && input.codeUnitAt(0) >= 32) {
      _currentCommandBuffer += input;
      terminal.write(input);
      return;
    }
    session.stdin.add(utf8.encode(input));
  }

  void _updateCommandBuffer(String command) {
    for (int i = 0; i < _currentCommandBuffer.length; i++) terminal.write('\b \b');
    _currentCommandBuffer = command;
    terminal.write(command);
  }

  void _clearCommandBuffer() {
    for (int i = 0; i < _currentCommandBuffer.length; i++) terminal.write('\b \b');
    _currentCommandBuffer = "";
  }

  void _startUniversalSync(SSHSession session) {
    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      attempts++;
      if (mounted && terminal.viewWidth > 0) {
        session.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
        await _activeServer!.sshService.runSingleCommand(
            "stty cols ${terminal.viewWidth} rows ${terminal.viewHeight}");
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
      length: widget.isTemporarySession ? 1 : 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: Column(
            children: [
              Text(
                widget.isTemporarySession ? 'Sesión Temporal' : widget.serverConfig.host,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(connStr, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              if (!widget.isTemporarySession) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(distroIcon, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Column(children: [
                      Text(distroName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                      Text('Package Manager: $pkgManager', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ]),
                  ],
                ),
              ],
            ],
          ),
          centerTitle: true,
          bottom: widget.isTemporarySession
              ? null
              : const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            tabs: [
              Tab(text: 'Monitoreo'),
              Tab(text: 'Terminal'),
              Tab(text: 'Archivos'),
              Tab(text: 'Apps Manager'),
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
              serverController: widget.serverController,
              activeServer: _activeServer,
            ),
          ],
        ),
      ),
    );
  }
}