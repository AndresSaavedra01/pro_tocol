import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:pro_tocol/model/entities/chat_message.dart';
import 'package:pro_tocol/view/components/chat_bubble.dart';
import 'package:pro_tocol/view/theme/AppColors.dart';

import '../../../controller/ChatIaController.dart';
import '../../components/TypingIndicatorBubble.dart';

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
    widget.controller.enviarMensajeUsuario(texto, onError: (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error en el Agente de IA: $error',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // 1. ÁREA DEL HISTORIAL DE MENSAJES
          Expanded(
            child: ctrl.mensajes.isEmpty && !ctrl.isSending
                ? _buildEmptyState()
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              itemCount: ctrl.mensajes.length + (ctrl.awaitingFirstChunk ? 1 : 0),
              itemBuilder: (context, index) {
                // Si está esperando el primer fragmento del stream inicial, mostramos el indicador de escritura
                if (index == ctrl.mensajes.length) {
                  return const TypingIndicatorBubble();
                }

                final msg = ctrl.mensajes[index];

                // Identificamos visualmente si la burbuja actual es un estado del agente en ejecución
                final isAgentExecuting = msg.text.startsWith("🔍 Ejecutando:") ||
                    msg.text.startsWith("🧠 Analizando");

                return ChatBubble(
                  message: msg,
                  // Customizamos el diseño si es un estado interno del agente
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

  // Vista que aparece si no hay conversación previa
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: AppColors.primary.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            '¿En qué puedo ayudarte hoy?',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Tatiana puede analizar la salud de tu servidor, generar scripts automatizados o inspeccionar configuraciones en tiempo real usando comandos SSH.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // Selector entre Modo Conversación y Modo Script Automático
  Widget _buildModeSelector(ChatIaController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: AppColors.surfaceHighlight.withOpacity(0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                ctrl.isScriptMode ? Icons.code_rounded : Icons.forum_rounded,
                size: 16,
                color: ctrl.isScriptMode ? AppColors.background : AppColors.primary,
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
            activeColor: AppColors.background,
            activeTrackColor: AppColors.background.withOpacity(0.3),
            inactiveThumbColor: AppColors.textMuted,
            // Desactivar el interruptor si la IA está operando
            onChanged: ctrl.isSending ? null : (val) => ctrl.toggleScriptMode(val),
          ),
        ],
      ),
    );
  }

  // Barra de herramientas inferior con el TextField
  Widget _buildInputBar(ChatIaController ctrl) {
    return Container(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 16.0, top: 8.0),
      color: AppColors.surfaceHighlight,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Botón para borrar el historial de chat (deshabilitado si está enviando)
            IconButton(
              onPressed: ctrl.isSending ? null : ctrl.deleteAllChat,
              icon: const Icon(Icons.delete_outline),
              color: AppColors.textMuted,
              tooltip: 'Borrar historial',
            ),
            const SizedBox(width: 8),

            // Entrada de texto
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !ctrl.isSending, // Bloquea la entrada si el agente está en medio de una tarea
                decoration: InputDecoration(
                  hintText: ctrl.isScriptMode ? "Dile qué automatizar..." : "Pregúntale a la IA...",
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                style: const TextStyle(color: AppColors.textPrimary),
                onSubmitted: ctrl.isSending ? null : (_) => _enviarMensaje(),
              ),
            ),
            const SizedBox(width: 10),

            // Botón de Enviar / Cargando Dinámico
            FloatingActionButton(
              mini: true,
              backgroundColor: ctrl.isSending ? AppColors.textMuted : AppColors.primary,
              onPressed: ctrl.isSending ? null : _enviarMensaje,
              child: ctrl.isSending
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            )
          ],
        ),
      ),
    );
  }
}