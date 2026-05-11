import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';
import '../../model/entities/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final void Function(String command)? onExecuteCommand;

  const ChatBubble({super.key, required this.message, this.onExecuteCommand});

  static final RegExp _codeBlockRegex = RegExp(r'```[\w]*\n([\s\S]*?)\n```');

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Comando copiado al portapapeles 📋'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final styleSheet = MarkdownStyleSheet(
      p: const TextStyle(color: Colors.white, fontSize: 15),
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

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.blue[800] : Colors.grey[850],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isUser ? 16 : 0),
            bottomRight: Radius.circular(message.isUser ? 0 : 16),
          ),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isUser)
              Text(
                message.text,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            else
              ..._buildAiContent(styleSheet),
            
            if (!message.isUser) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white70, size: 20),
                  tooltip: 'Copiar comando',
                  onPressed: () => _copyToClipboard(context),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAiContent(MarkdownStyleSheet styleSheet) {
    final matches = _codeBlockRegex.allMatches(message.text).toList();
    if (matches.isEmpty) {
      return [MarkdownBody(data: message.text, styleSheet: styleSheet)];
    }

    final widgets = <Widget>[];
    var lastIndex = 0;

    for (final match in matches) {
      final before = message.text.substring(lastIndex, match.start);
      if (before.trim().isNotEmpty) {
        widgets.add(MarkdownBody(data: before, styleSheet: styleSheet));
      }

      final fencedBlock = message.text.substring(match.start, match.end);
      widgets.add(MarkdownBody(data: fencedBlock, styleSheet: styleSheet));

      final codeContent = match.group(1)?.trim() ?? '';
      if (codeContent.isNotEmpty && onExecuteCommand != null) {
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
        onPressed: () => onExecuteCommand?.call(command),
      ),
    );
  }
}