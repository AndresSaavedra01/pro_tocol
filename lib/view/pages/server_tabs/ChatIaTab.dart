import 'package:flutter/material.dart';
import 'package:pro_tocol/model/entities/chat_message.dart';
import 'package:pro_tocol/view/components/chat_bubble.dart';
import 'package:pro_tocol/view/theme/AppColors.dart'; 

class ChatIaTab extends StatefulWidget {
  const ChatIaTab({super.key});

  @override
  State<ChatIaTab> createState() => _ChatIaTabState();
}

class _ChatIaTabState extends State<ChatIaTab> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  final List<ChatMessage> _mensajes = [
    ChatMessage(
      text: "¡Hola! Soy tu asistente de Pro-Tocol impulsado por IA. ¿En qué te puedo ayudar con este servidor hoy?",
      isUser: false,
    )
  ];

  void _enviarMensaje() {
    if (_textController.text.trim().isEmpty) return;

    final textoUsuario = _textController.text;

    setState(() {
      _mensajes.add(ChatMessage(text: textoUsuario, isUser: true));
    });

    _textController.clear();
    _hacerScrollHaciaAbajo();

    // Simulación de respuesta de la IA
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _mensajes.add(
            ChatMessage(
              text: "He recibido tu mensaje sobre: *$textoUsuario*. Estoy listo para ayudarte a gestionar tu servidor.",
              isUser: false,
            ),
          );
        });
        _hacerScrollHaciaAbajo();
      }
    });
  }

  void _hacerScrollHaciaAbajo() {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Lista de mensajes
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12.0),
            itemCount: _mensajes.length,
            itemBuilder: (context, index) {
              return ChatBubble(message: _mensajes[index]);
            },
          ),
        ),
        
        // Caja de entrada de texto (Input)
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
                
                //  boton de enviar
                Material(
                  color: AppColors.primary, 
                  shape: const CircleBorder(), 
                  elevation: 4, 
                  clipBehavior: Clip.antiAlias, 
                  child: InkWell(
                    onTap: _enviarMensaje,

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