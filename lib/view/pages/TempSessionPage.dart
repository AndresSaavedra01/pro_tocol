import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pro_tocol/injection.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';

import 'package:pro_tocol/controller/TempSessionController.dart';
import 'package:pro_tocol/model/entities/TempSession.dart';
import 'package:pro_tocol/model/entities/TempSessionConfig.dart';

import '../theme/AppColors.dart';
// Asegúrate de que esta ruta de importación coincida con tu estructura de carpetas
import 'package:pro_tocol/view/pages/server_tabs/TerminalTab.dart';


class TempSessionPage extends StatefulWidget {
  final TempSessionConfig tempConfig;

  const TempSessionPage({
    super.key,
    required this.tempConfig,
  });

  @override
  State<TempSessionPage> createState() => _TempSessionPageState();
  TempSessionController get _tempController => getIt<TempSessionController>();
}

class _TempSessionPageState extends State<TempSessionPage> {
  late final Terminal terminal;
  TempSession? _activeSession;
  SSHSession? _shellSession;

  @override
  void initState() {
    super.initState();
    terminal = getIt<Terminal>();
    _connectToTerminal();
  }

  @override
  void dispose() {
    _shellSession?.close(); // Es vital cerrar el shell al salir de la vista
    super.dispose();
  }

  Future<void> _connectToTerminal() async {
    try {
      // 1. Obtenemos la sesión viva desde la memoria RAM del controlador
      _activeSession = widget._tempController.getValidSession(widget.tempConfig.host);

      // 2. Iniciamos la sesión con un tamaño base seguro (80x24 mínimo)
      _shellSession = await _activeSession!.sshService.createTerminal(
        width: terminal.viewWidth > 0 ? terminal.viewWidth : 80,
        height: terminal.viewHeight > 0 ? terminal.viewHeight : 24,
      );

      // 3. Listener para cambios dinámicos de tamaño
      terminal.onResize = (width, height, cursorWidth, cursorHeight) {
        if (width > 0 && height > 0) {
          // Sin usar pixelWidth/pixelHeight para evitar errores
          _shellSession?.resizeTerminal(width, height);
        }
      };

      // 4. Sincronización inicial
      _startUniversalSync(_shellSession!);

      // 5. Escuchamos la salida del servidor y la escribimos en la terminal
      _shellSession!.stdout.listen((data) {
        if (mounted) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        }
      });

      _shellSession!.stderr.listen((data) {
        if (mounted) {
          terminal.write(utf8.decode(data, allowMalformed: true));
        }
      });

      // --- EL CAMBIO CLAVE AQUÍ ---
      // Enviamos la tecla directamente a stdin.
      // Esto permite que el servidor gestione el cursor y el eco de las letras.
      terminal.onOutput = (input) {
        _shellSession?.stdin.add(utf8.encode(input));
      };

      // Limpiamos la terminal local antes de que el servidor tome el control
      terminal.write('\x1Bc');

    } catch (e) {
      if (mounted) {
        terminal.write('\x1B[31mError al iniciar la terminal: $e\x1B[0m\r\n');
      }
    }
  }

  void _startUniversalSync(SSHSession session) {
    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 300), (timer) {
      attempts++;
      if (mounted && terminal.viewWidth > 0) {
        // Solo se hace resize nativo.
        session.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
        if (attempts >= 3) timer.cancel();
      }
      if (attempts > 10) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionString = "${widget.tempConfig.username}@${widget.tempConfig.host}";

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Column(
          children: [
            const Text(
                'Sesión Temporal',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)
            ),
            Text(
                connectionString,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
      ),
      // --- USO LIMPIO Y DIRECTO DE TU WIDGET REUTILIZABLE ---
      body: TerminalTab(terminal: terminal),
    );
  }
}