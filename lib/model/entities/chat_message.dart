class ChatMessage {
  final String text;
  final bool isUser; // true si lo escribió el usuario, false si es la IA

  ChatMessage({
    required this.text,
    required this.isUser,
  });
}