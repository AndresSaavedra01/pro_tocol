import 'package:flutter/material.dart';
import 'package:pro_tocol/view/components/chat_bubble.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';

import '../../../controller/ChatIaController.dart';

class ChatIaTab extends StatefulWidget {
  final ChatIaController controller;

  const ChatIaTab({
    super.key,
    required this.controller,
  });

  @override
  State<ChatIaTab> createState() => _ChatIaTabState();
}

class _ChatIaTabState extends State<ChatIaTab> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
    widget.controller.cargarHistorial();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _enviarMensaje() {
    final texto = _textController.text.trim();
    if (texto.isEmpty) return;

    _textController.clear();
    widget.controller.enviarMensajeUsuario(
        texto,
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error en el Agente de IA: $error',
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;

    return Container(
      color: AppColors.background, // Cambiado de surface a background para mayor profundidad
      child: Column(
        children: [
          // 1. ÁREA DEL HISTORIAL DE MENSAJES
          Expanded(
            child: ctrl.mensajes.isEmpty && !ctrl.isSending
                ? _buildEmptyState()
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              itemCount: ctrl.mensajes.length + (ctrl.awaitingFirstChunk ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == ctrl.mensajes.length) {
                  return const _TypingIndicatorBubble();
                }

                final msg = ctrl.mensajes[index];

                // Identificamos visualmente si la burbuja actual es un estado del agente en ejecución
                final isAgentExecuting = msg.text.startsWith("🔍") ||
                    msg.text.startsWith("🧠") ||
                    msg.text.startsWith("💻");

                return ChatBubble(
                  message: msg,
                  isSystemStatus: isAgentExecuting,
                  onEditSubmitted: (newText) => ctrl.updateMessageContent(msg.text, newText, index),
                  onDelete: () => ctrl.deleteMessage(msg.text),
                );
              },
            ),
          ),

          // 2. CONTROLES DE MODO (CHAT NORMAL VS GENERADOR DE SCRIPTS)
          _buildModeSelector(ctrl),

          // 3. BARRA DE ENTRADA DE TEXTO Y ACCIONES
          _buildInputBar(ctrl),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: AppColors.primary.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text(
            '¿En qué puedo ayudarte hoy?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Tatiana puede analizar la salud de tu servidor, generar scripts automatizados o inspeccionar configuraciones en tiempo real usando comandos SSH.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(ChatIaController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      color: AppColors.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                ctrl.isScriptMode ? Icons.code_rounded : Icons.forum_rounded,
                size: 16,
                color: ctrl.isScriptMode ? AppColors.secondary : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                ctrl.isScriptMode ? "Modo: Generador de Scripts Bash" : "Modo: Asistente del Servidor (Tatiana)",
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          Switch(
            value: ctrl.isScriptMode,
            activeColor: AppColors.secondary,
            activeTrackColor: AppColors.secondary.withOpacity(0.2),
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.surfaceHighlight,
            onChanged: ctrl.isSending ? null : (val) => ctrl.toggleScriptMode(val),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ChatIaController ctrl) {
    return Container(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 20.0, top: 10.0),
      color: AppColors.surface, // Sincronizado con el fondo de la sección de controles
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              onPressed: ctrl.isSending ? null : ctrl.deleteAllChat,
              icon: const Icon(Icons.delete_outline),
              color: AppColors.error.withOpacity(0.8),
              tooltip: 'Borrar historial',
            ),
            const SizedBox(width: 4),

            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !ctrl.isSending,
                decoration: InputDecoration(
                  hintText: ctrl.isScriptMode ? "Dile qué automatizar..." : "Pregúntale a la IA...",
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  filled: true,
                  fillColor: AppColors.surfaceHighlight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24.0), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                onSubmitted: ctrl.isSending ? null : (_) => _enviarMensaje(),
              ),
            ),
            const SizedBox(width: 8),

            FloatingActionButton(
              mini: true,
              elevation: 0,
              backgroundColor: ctrl.isSending ? AppColors.surfaceHighlight : AppColors.primary,
              onPressed: ctrl.isSending ? null : _enviarMensaje,
              child: ctrl.isSending
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
              )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 16),
            )
          ],
        ),
      ),
    );
  }
}

class _TypingIndicatorBubble extends StatelessWidget {
  const _TypingIndicatorBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('Pensando...', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            SizedBox(height: 8),
            SizedBox(
              width: 80,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: AppColors.surfaceHighlight,
                valueColor: AlwaysStoppedAnimation(AppColors.secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}