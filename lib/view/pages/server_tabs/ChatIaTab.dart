import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_tocol/injection.dart';
import 'package:pro_tocol/model/entities/Server.dart';
import 'package:pro_tocol/model/entities/chat_message.dart';
import 'package:pro_tocol/model/entities/chat_message_entity.dart';
import 'package:pro_tocol/model/repositories/ChatHistoryRepository.dart';
import 'package:pro_tocol/model/services/ia_service.dart';
import 'package:pro_tocol/view/components/chat_bubble.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';
import 'package:xterm/xterm.dart';

class ChatIaController extends ChangeNotifier {
  final List<_ChatIaPrompt> _queue = [];

  void submitPrompt(String prompt, {String? userDisplay}) {
    _queue.add(_ChatIaPrompt(prompt, userDisplay));
    notifyListeners();
  }

  _ChatIaPrompt? nextPending() {
    if (_queue.isEmpty) return null;
    return _queue.removeAt(0);
  }

  bool get hasPending => _queue.isNotEmpty;
}

class _ChatIaPrompt {
  final String prompt;
  final String? userDisplay;

  const _ChatIaPrompt(this.prompt, this.userDisplay);
}

class ChatIaTab extends StatefulWidget {
  final String serverIp;
  final ChatIaController? controller;
  final String profileId;
  final Server? activeServer; // Para ejecutar scripts vía SSH/SFTP

  const ChatIaTab({
    super.key,
    required this.serverIp,
    required this.profileId,
    this.activeServer,
    this.controller,
  });

  @override
  State<ChatIaTab> createState() => _ChatIaTabState();
}

class _ChatIaTabState extends State<ChatIaTab> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _awaitingFirstChunk = false;
  bool _isScriptMode = false; // Modo generación de scripts

  IAService get _iaService => getIt<IAService>();
  ChatHistoryRepository get _historyRepo => getIt<ChatHistoryRepository>();

  List<ChatMessage> _mensajes = [];

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
    widget.controller?.addListener(_handleExternalPrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleExternalPrompt());
  }

  Future<void> _cargarHistorial() async {
    final mensajesDb = await _historyRepo.getMessagesByServerAndProfile(
        widget.serverIp, widget.profileId);
    setState(() {
      if (mensajesDb.isEmpty) {
        _mensajes = [
          ChatMessage(
            text:
                "¡Hola! Soy tu asistente de Pro-Tocol. ¿En qué te puedo ayudar con el servidor ${widget.serverIp}?",
            isUser: false,
          )
        ];
      } else {
        _mensajes = mensajesDb
          .map((e) => ChatMessage(
            text: e.editedContent ?? e.content, isUser: e.role == 'user'))
          .toList();
      }
    });
    _scrollToBottom();
  }

  Future<void> _enviarMensaje() async {
    if (_isSending) return;
    final textoUsuario = _textController.text.trim();
    if (textoUsuario.isEmpty) return;

    await _historyRepo.saveMessage(ChatMessageEntity(
      serverIp: widget.serverIp,
      profileId: widget.profileId,
      role: 'user',
      content: textoUsuario,
      timestamp: DateTime.now(),
    ));

    _textController.clear();
    await _sendPromptInternal(prompt: textoUsuario, userDisplay: textoUsuario);
  }

  void _handleExternalPrompt() {
    if (!mounted) return;
    _drainExternalQueue();
  }

  void _drainExternalQueue() {
    if (_isSending) return;
    final controller = widget.controller;
    if (controller == null) return;
    final next = controller.nextPending();
    if (next == null) return;
    _sendPromptInternal(
      prompt: next.prompt,
      userDisplay: next.userDisplay ?? 'Analiza este error del terminal.',
    );
  }

  Future<void> _sendPromptInternal({
    required String prompt,
    required String userDisplay,
  }) async {
    if (_isSending) return;

    setState(() {
      _mensajes.add(ChatMessage(text: userDisplay, isUser: true));
      _isSending = true;
    });
    _scrollToBottom();

    if (_isScriptMode) {
      await _handleScriptGeneration(prompt);
    } else {
      await _handleNormalChat(prompt);
    }
  }

  // ================= MODO SCRIPT (nuevo) =================

  Future<void> _handleScriptGeneration(String prompt) async {
    setState(() {
      _awaitingFirstChunk = true;
      _mensajes.add(ChatMessage(text: '', isUser: false)); // placeholder
    });
    final aiIndex = _mensajes.length - 1;

    try {
      final scriptCode = await _iaService.generarScript(prompt);

      setState(() {
        _awaitingFirstChunk = false;
        _mensajes[aiIndex] = ChatMessage(
            text: "He generado tu script. Revisa la ventana emergente para confirmarlo.",
            isUser: false);
      });

      if (mounted) _showScriptConfirmationDialog(scriptCode);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _awaitingFirstChunk = false;
        _mensajes[aiIndex] =
            ChatMessage(text: "Error al generar script: $e", isUser: false);
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  void _showScriptConfirmationDialog(String scriptCode) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Script Generado",
            style: TextStyle(color: AppColors.textPrimary)),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.black54,
            child: Text(
              scriptCode,
              style: const TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar",
                  style: TextStyle(color: Colors.redAccent))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.play_arrow, color: Colors.white),
            label: const Text("Ejecutar en Servidor",
                style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(context);
              _executeScriptOnServer(scriptCode);
            },
          )
        ],
      ),
    );
  }

  Future<void> _executeScriptOnServer(String scriptCode) async {
    if (widget.activeServer?.sshService == null ||
        widget.activeServer!.sshService.sftp == null) {
      _addSystemMessage("Error: No hay conexión SSH/SFTP activa con el servidor.");
      return;
    }

    setState(() => _isSending = true);
    _addSystemMessage("Iniciando despliegue y ejecución del script en /tmp/scripts...");

    try {
      final sftp = widget.activeServer!.sshService.sftp!;
      final ssh = widget.activeServer!.sshService;

      // Crear carpeta /tmp/scripts (ignorar si ya existe)
      try {
        await sftp.createDirectory("/tmp/scripts");
      } catch (_) {}

      // Guardar archivo temporal en el dispositivo
      final tempDir = await getTemporaryDirectory();
      final fileName = "auto_${DateTime.now().millisecondsSinceEpoch}.sh";
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(scriptCode);

      // ¡CORREGIDO! Subir archivo usando SFTP a /tmp/scripts
      final remotePath = "/tmp/scripts/$fileName";
      await sftp.uploadFile(tempFile.path, remotePath);

      // ¡CORREGIDO! Dar permisos, limpiar retornos de carro (sed) y ejecutar con SSHService
      final comandoEjecucion = "sed -i 's/\\r\$//' $remotePath && chmod +x $remotePath && $remotePath";
      final resultado = await ssh.runSingleCommand(comandoEjecucion);

      _addSystemMessage(
          " Ejecucion Finalizada.\n\nSalida del terminal:\n```text\n$resultado\n```");
          
      // Opcional: Borramos el archivo temporal del celular para no llenarle la memoria
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

    } catch (e) {
      _addSystemMessage(" Fallo critico durante el despliegue: $e");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _addSystemMessage(String text) {
    setState(() => _mensajes.add(ChatMessage(text: text, isUser: false)));
    _scrollToBottom();
  }

  Future<ChatMessageEntity?> _findUserMessageEntityByText(String text) async {
    final mensajesDb = await _historyRepo.getMessagesByServerAndProfile(
        widget.serverIp, widget.profileId);
    for (final entity in mensajesDb) {
      final display = entity.editedContent ?? entity.content;
      if (entity.role == 'user' && display == text) {
        return entity;
      }
    }
    return null;
  }

  Future<void> _deleteAllChat() async {
    await _historyRepo.deleteAllByServerAndProfile(
        widget.serverIp, widget.profileId);
    await _cargarHistorial();
  }

  Future<void> _editUserMessage(int index, ChatMessage message) async {
    final controller = TextEditingController(text: message.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Editar mensaje',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Editar mensaje...',
            hintStyle: TextStyle(color: AppColors.textMuted),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newText == null || newText.isEmpty) return;

    final entity = await _findUserMessageEntityByText(message.text);
    if (entity != null) {
      await _historyRepo.updateMessageContent(entity.id, newText);
    }
    if (!mounted) return;
    setState(() {
      _mensajes[index] = ChatMessage(text: newText, isUser: true);
    });
  }

  // ================= CHAT NORMAL (original) =================

  Future<void> _handleNormalChat(String prompt) async {
    setState(() {
      _mensajes.add(ChatMessage(text: '', isUser: false));
      _awaitingFirstChunk = true;
    });

    final aiIndex = _mensajes.length - 1;
    final buffer = StringBuffer();

    try {
      await for (final chunk in _iaService.generateStream(prompt, _mensajes)) {
        if (!mounted) return;
        if (chunk.isEmpty) continue;
        buffer.write(chunk);
        setState(() {
          if (_awaitingFirstChunk) _awaitingFirstChunk = false;
          _mensajes[aiIndex] = ChatMessage(text: buffer.toString(), isUser: false);
        });
        _scrollToBottom();
      }

      await _historyRepo.saveMessage(ChatMessageEntity(
        serverIp: widget.serverIp,
        profileId: widget.profileId,
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
      if (mounted) {
        _drainExternalQueue();
      }
    }
  }

  // ================= MÉTODOS AUXILIARES (originales) =================

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

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(fallbackMessage)));
  }

  // ================= BUILD =================

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
              if (message.isUser) {
                return Dismissible(
                  key: ValueKey(
                      _mensajes[index].hashCode.toString() + index.toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    color: Colors.redAccent,
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    final entity =
                        await _findUserMessageEntityByText(message.text);
                    if (entity != null) {
                      await _historyRepo.deleteMessage(entity.id);
                    }
                    if (!mounted) return;
                    setState(() {
                      _mensajes.removeAt(index);
                    });
                  },
                  child: GestureDetector(
                    onLongPress: () => _editUserMessage(index, message),
                    child: ChatBubble(
                      message: message,
                      onExecuteCommand: null,
                    ),
                  ),
                );
              }
              return ChatBubble(
                message: message,
                onExecuteCommand: _executeInTerminal,
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
                // Toggle para modo script
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Script",
                        style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    Switch(
                      value: _isScriptMode,
                      onChanged: _isSending ? null : (val) => setState(() => _isScriptMode = val),
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _isSending ? null : _deleteAllChat,
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.textMuted,
                  tooltip: 'Borrar historial',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_isSending,
                    decoration: InputDecoration(
                      hintText: _isScriptMode
                          ? "Dile qué automatizar..."
                          : "Pregúntale a la IA...",
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: _isSending
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.send_rounded,
                                color: Colors.white, size: 24),
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
    widget.controller?.removeListener(_handleExternalPrompt);
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
            Text('Escribiendo...',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
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