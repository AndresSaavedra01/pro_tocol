import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../theme/AppColors.dart';

class TerminalTab extends StatelessWidget {
  final Terminal terminal;

  const TerminalTab({super.key, required this.terminal});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.terminalBg,
      padding: const EdgeInsets.all(12.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TerminalView(
            terminal,
            autofocus: true,
            backgroundOpacity: 1,
            // ARREGLO: Esto evita que el teclado del móvil use texto predictivo
            // y rompa la sincronización de caracteres individuales con xterm
            keyboardType: TextInputType.visiblePassword,
            theme: TerminalTheme(
              cursor: AppColors.textPrimary,
              selection: Colors.blueAccent.withOpacity(0.4),
              foreground: AppColors.textPrimary,
              background: AppColors.background,
              black: Colors.black,
              red: AppColors.error,
              green: AppColors.success,
              yellow: Colors.yellowAccent,
              blue: Colors.blueAccent,
              magenta: Colors.purpleAccent,
              cyan: Colors.cyanAccent,
              white: AppColors.textPrimary,
              brightBlack: Colors.grey,
              brightRed: Colors.red,
              brightGreen: Colors.green,
              brightYellow: Colors.yellow,
              brightBlue: Colors.blue,
              brightMagenta: Colors.purple,
              brightCyan: Colors.cyan,
              brightWhite: Colors.white,
              searchHitBackground: Colors.yellowAccent.withOpacity(0.3),
              searchHitBackgroundCurrent: Colors.orangeAccent.withOpacity(0.5),
              searchHitForeground: Colors.black,
            ),
            textStyle: const TerminalStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }
}