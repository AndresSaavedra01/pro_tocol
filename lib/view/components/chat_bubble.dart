import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';
import '../../model/entities/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final void Function(String command)? onExecuteCommand;

  // Nuevos parámetros para soportar la IA Agéntica y edición
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
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (onEditSubmitted != null && controller.text.trim().isNotEmpty) {
                  onEditSubmitted!(controller.text.trim());
                }
              },
              child: const Text('Guardar')
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ESTILOS VISUALES DEPENDIENDO DEL TIPO DE MENSAJE
    final bgColor = isSystemStatus
        ? Colors.transparent
        : message.isUser
        ? AppColors.primary.withOpacity(0.2)
        : AppColors.surfaceHighlight;

    final borderColor = isSystemStatus
        ? AppColors.background.withOpacity(0.5)
        : Colors.transparent;

    final textColor = isSystemStatus
        ? AppColors.textMuted
        : Colors.white;

    final styleSheet = MarkdownStyleSheet(
      p: TextStyle(
        color: textColor,
        fontSize: isSystemStatus ? 13 : 15,
        fontStyle: isSystemStatus ? FontStyle.italic : FontStyle.normal,
      ),
      code: TextStyle(
        backgroundColor: Colors.black,
        color: Colors.greenAccent[400],
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    Widget bubbleContent = Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: message.isUser ? const Radius.circular(16) : const Radius.circular(4),
          bottomRight: message.isUser ? const Radius.circular(4) : const Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildContent(context, styleSheet),
      ),
    );

    // Si es del usuario, permitimos gestos para editar (Long Press) y borrar (Doble Tap)
    if (message.isUser) {
      bubbleContent = GestureDetector(
        onLongPress: () => _showEditDialog(context),
        onDoubleTap: onDelete,
        child: bubbleContent,
      );
    }

    return Align(
      alignment: isSystemStatus
          ? Alignment.center // Los estados del sistema los centramos
          : message.isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * (isSystemStatus ? 0.9 : 0.85),
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
      widgets.add(MarkdownBody(data: fencedBlock, styleSheet: styleSheet));

      final codeContent = match.group(1)?.trim() ?? '';
      // No mostramos botón de ejecutar si es un estado del sistema
      if (codeContent.isNotEmpty && onExecuteCommand != null && !isSystemStatus) {
        widgets.add(const SizedBox(height: 6));
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
      child: TextButton.icon(
        icon: const Icon(Icons.terminal, size: 18, color: AppColors.primary),
        label: const Text('Ejecutar en Terminal'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceHighlight,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.primary),
          ),
        ),
        onPressed: () => onExecuteCommand!(command),
      ),
    );
  }
}