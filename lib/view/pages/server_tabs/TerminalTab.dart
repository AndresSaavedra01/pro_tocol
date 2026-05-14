import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../theme/AppColors.dart';

class TerminalTab extends StatelessWidget {
  final Terminal terminal;
  final ValueListenable<String?>? errorOutputListenable;
  final ValueChanged<String>? onAskProTocol;

  const TerminalTab({
    super.key,
    required this.terminal,
    this.errorOutputListenable,
    this.onAskProTocol,
  });

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
          child: Stack(
            children: [
              Positioned.fill(
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
              if (errorOutputListenable != null && onAskProTocol != null)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: ValueListenableBuilder<String?>(
                    valueListenable: errorOutputListenable!,
                    builder: (context, errorOutput, _) {
                      if (errorOutput == null || errorOutput.trim().isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return ElevatedButton.icon(
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('Preguntar a Pro-Tocol'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 6,
                        ),
                        onPressed: () => onAskProTocol?.call(errorOutput),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}