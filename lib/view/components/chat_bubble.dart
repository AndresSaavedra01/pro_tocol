import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';
import '../../model/entities/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final void Function(String command)? onExecuteCommand;

  // Parámetros para soportar la IA Agéntica y edición
  final bool isSystemStatus;
  final Function(String)? onEditSubmitted;
  final VoidCallback? onDelete;

  const ChatBubble({
    super.key,
    required this.message,
    this.onExecuteCommand,
    this.isSystemStatus = false,
    this.onEditSubmitted,
    this.onDelete,
  });

  static final RegExp _codeBlockRegex = RegExp(r'```[\w]*\n([\s\S]*?)\n```');

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado al portapapeles 📋'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController(text: message.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Editar mensaje', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted))
          ),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (onEditSubmitted != null && controller.text.trim().isNotEmpty) {
                  onEditSubmitted!(controller.text.trim());
                }
              },
              child: const Text('Guardar', style: TextStyle(color: AppColors.secondary))
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.isUser;

    // ESTILOS VISUALES UNIFICADOS
    // Ahora tanto la IA como los comandos usan el mismo fondo oscuro
    final bgColor = isUser ? AppColors.primary : AppColors.surfaceHighlight;

    // Los comandos tendrán un borde cyan para diferenciarse sutilmente, la IA un borde normal
    final borderColor = isSystemStatus
        ? AppColors.secondary.withOpacity(0.4)
        : (isUser ? Colors.transparent : AppColors.border.withOpacity(0.1));

    // Todos usan texto blanco claro
    final textColor = isUser ? Colors.white : AppColors.textPrimary;

    // 1. Teñimos TODO el textTheme del color correcto (blanco) para evitar fugas de texto negro
    final customTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor, // Esto fuerza a que títulos y cabeceras de tabla sean claros
      ).copyWith(
        bodyMedium: TextStyle(color: textColor, fontSize: 15, height: 1.4),
      ),
    );

    // 2. Cargamos el StyleSheet directamente desde el tema heredado
    final styleSheet = MarkdownStyleSheet.fromTheme(customTheme).copyWith(
      // Reforzamos las tablas
      tableHead: TextStyle(
        color: textColor,
        fontWeight: FontWeight.bold,
      ),
      tableBody: TextStyle(
        color: textColor,
      ),
      tableBorder: TableBorder.all(
        color: AppColors.border.withOpacity(0.3),
        width: 1,
      ),

      // Forzar que las citas (blockquote) no hereden fondos cyan del sistema
      blockquoteDecoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(left: BorderSide(color: AppColors.secondary, width: 4)),
      ),
      blockquote: TextStyle(color: textColor.withOpacity(0.7), fontStyle: FontStyle.italic),

      // Estilo armónico para comandos en línea sin fondo molesto
      code: const TextStyle(
        backgroundColor: Colors.transparent,
        color: Color(0xFFE5C07B), // Amarillo/Dorado sutil tipo VSCode
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
      ),

      // Bloques grandes de código (La terminal)
      codeblockDecoration: BoxDecoration(
        color: AppColors.terminalBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceHighlight, width: 1.5),
      ),
    );

    Widget bubbleContent = Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          // Las burbujas de la IA y comandos comparten la misma forma
          bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
          bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildContent(context, styleSheet),
      ),
    );

    if (isUser) {
      bubbleContent = GestureDetector(
        onLongPress: () => _showEditDialog(context),
        onDoubleTap: onDelete,
        child: bubbleContent,
      );
    }

    // AHORA TODO FLUYE DE IZQUIERDA A DERECHA, SIN GLOBOS CENTRADOS
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: bubbleContent,
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, MarkdownStyleSheet styleSheet) {
    List<Widget> widgets = [];
    int lastIndex = 0;

    final matches = _codeBlockRegex.allMatches(message.text);

    for (final match in matches) {
      final before = message.text.substring(lastIndex, match.start);
      if (before.trim().isNotEmpty) {
        widgets.add(MarkdownBody(data: before, styleSheet: styleSheet));
      }

      final fencedBlock = message.text.substring(match.start, match.end);
      widgets.add(const SizedBox(height: 6));
      widgets.add(MarkdownBody(data: fencedBlock, styleSheet: styleSheet));
      widgets.add(const SizedBox(height: 6));

      final codeContent = match.group(1)?.trim() ?? '';
      if (codeContent.isNotEmpty && onExecuteCommand != null && !isSystemStatus) {
        widgets.add(_buildExecuteButton(codeContent));
      }

      lastIndex = match.end;
    }

    final after = message.text.substring(lastIndex);
    if (after.trim().isNotEmpty) {
      widgets.add(MarkdownBody(data: after, styleSheet: styleSheet));
    }

    return widgets;
  }

  Widget _buildExecuteButton(String command) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: TextButton.icon(
          icon: const Icon(Icons.terminal_rounded, size: 18, color: AppColors.secondary),
          label: const Text('Ejecutar en Terminal'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.secondary,
            backgroundColor: AppColors.secondary.withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: AppColors.secondary.withOpacity(0.5), width: 1),
            ),
          ),
          onPressed: () => onExecuteCommand!(command),
        ),
      ),
    );
  }
}