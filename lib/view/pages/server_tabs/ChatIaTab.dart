import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pro_tocol/injection.dart';
import 'package:pro_tocol/model/entities/chat_message.dart';
import 'package:pro_tocol/model/entities/chat_message_entity.dart';
import 'package:pro_tocol/model/repositories/ChatHistoryRepository.dart';
import 'package:pro_tocol/model/services/ia_service.dart';
import 'package:pro_tocol/view/components/chat_bubble.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';
import 'package:xterm/xterm.dart';

class ChatIaTab extends StatefulWidget {
  final String serverIp;
  const ChatIaTab({super.key,required this.serverIp,});

  @override
  State<ChatIaTab> createState() => _ChatIaTabState();
}

class _ChatIaTabState extends State<ChatIaTab> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _awaitingFirstChunk = false;

  IAService get _iaService => getIt<IAService>();
  ChatHistoryRepository get _historyRepo => getIt<ChatHistoryRepository>();

  // La lista empieza vacía porque se cargará de la DB
  List<ChatMessage> _mensajes = [];

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    final mensajesDb = await _historyRepo.getMessagesByServer(widget.serverIp);

    setState(() {
      if (mensajesDb.isEmpty) {
        // Si no hay mensajes guardados, mostramos el saludo inicial
        _mensajes = [
          ChatMessage(
            text: "¡Hola! Soy tu asistente de Pro-Tocol. ¿En qué te puedo ayudar con el servidor ${widget.serverIp}?",
            isUser: false,
          )
        ];
      } else {
        // Convertimos las entidades de Isar al modelo ChatMessage de la UI
        _mensajes = mensajesDb.map((e) => ChatMessage(
          text: e.content,
          isUser: e.role == 'user',
        )).toList();
      }
    });
    _scrollToBottom();
  }

  Future<void> _enviarMensaje() async {
    if (_isSending) return;
    final textoUsuario = _textController.text.trim();
    if (textoUsuario.isEmpty) return;

    // Guardar mensaje del usuario en la Base de Datos
    await _historyRepo.saveMessage(ChatMessageEntity(
      serverIp: widget.serverIp,
      role: 'user',
      content: textoUsuario,
      timestamp: DateTime.now(),
    ));

    setState(() {
      _mensajes.add(ChatMessage(text: textoUsuario, isUser: true));
      _mensajes.add(ChatMessage(text: '', isUser: false)); // Espacio para la respuesta de la IA
      _isSending = true;
      _awaitingFirstChunk = true;
    });

    _textController.clear();
    _scrollToBottom();

    final aiIndex = _mensajes.length - 1;
    final buffer = StringBuffer();

    try {
      await for (final chunk in _iaService.generateStream(textoUsuario, _mensajes)) {
        if (!mounted) return;
        if (chunk.isEmpty) continue;
        buffer.write(chunk);
        setState(() {
          if (_awaitingFirstChunk) {
            _awaitingFirstChunk = false;
          }
          _mensajes[aiIndex] = ChatMessage(text: buffer.toString(), isUser: false);
        });
        _scrollToBottom();
      }

      // Guardar la respuesta completa de la IA en la Base de Datos
      await _historyRepo.saveMessage(ChatMessageEntity(
        serverIp: widget.serverIp,
        role: 'assistant',
        content: buffer.toString(),
        timestamp: DateTime.now(),
      ));

    } catch (e) {
      if (!mounted) return;
      final friendly = _friendlyErrorMessage(e);
      setState(() {
        _awaitingFirstChunk = false;
        _mensajes[aiIndex] = ChatMessage(text: friendly, isUser: false);
      });
      _showConfigPromptIfNeeded(e, friendly);
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _awaitingFirstChunk = false;
        });
      }
    }
  }

  Future<void> _executeInTerminal(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;

    final isMultiLine = trimmed.contains('\n') || trimmed.contains('\r');
    if (isMultiLine) {
      final shouldRun = await _confirmMultiLineCommand(trimmed);
      if (!shouldRun) return;
    }

    final terminal = getIt<Terminal>();
    terminal.textInput(trimmed);
    terminal.keyInput(TerminalKey.enter);
    _scrollToBottom();
  }

  Future<bool> _confirmMultiLineCommand(String command) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Ejecutar comando de varias lineas',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Text(
            'Este comando tiene varias lineas. Quieres ejecutarlo en la terminal activa?',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('Ejecutar'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _friendlyErrorMessage(Object error) {
    final message = error.toString();
    if (_isConfigError(message)) {
      return 'La IA no esta configurada o faltan credenciales. Ve a Ajustes de IA.';
    }
    return 'No se pudo obtener respuesta: $message';
  }

  bool _isConfigError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('configuracion') ||
        lower.contains('token') ||
        lower.contains('modelo');
  }

  void _showConfigPromptIfNeeded(Object error, String fallbackMessage) {
    final message = error.toString();
    if (_isConfigError(message)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Configura la IA para continuar.'),
          action: SnackBarAction(
            label: 'Configurar',
            onPressed: () => context.push('/ai-settings'),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(fallbackMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12.0),
            itemCount: _mensajes.length,
            itemBuilder: (context, index) {
              final message = _mensajes[index];
              if (!message.isUser && message.text.isEmpty && _awaitingFirstChunk) {
                return const _TypingIndicatorBubble();
              }
              return ChatBubble(
                message: message,
                onExecuteCommand: message.isUser ? null : _executeInTerminal,
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: AppColors.surface,
            boxShadow: [
              BoxShadow(
                offset: const Offset(0, -2),
                blurRadius: 10,
                color: Colors.black.withOpacity(0.2),
              )
            ],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_isSending,
                    decoration: InputDecoration(
                      hintText: "Pregúntale a la IA...",
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    style: const TextStyle(color: AppColors.textPrimary),
                    onSubmitted: (_) => _enviarMensaje(),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  elevation: 4,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _isSending ? null : _enviarMensaje,
                    splashColor: Colors.white.withOpacity(0.1),
                    highlightColor: Colors.white.withOpacity(0.05),
                    child: Ink(
                      child: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _TypingIndicatorBubble extends StatelessWidget {
  const _TypingIndicatorBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Escribiendo...', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            SizedBox(height: 6),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
