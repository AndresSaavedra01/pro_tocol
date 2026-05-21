import 'package:isar/isar.dart';

part 'chat_message_entity.g.dart';

@collection
class ChatMessageEntity {
  Id id = Isar.autoIncrement;

  
  final String serverIp; // Para filtrar mensajes por servidor
  final String profileId; // Para filtrar mensajes por perfil/usuario
  final String role;     // 'user' o 'assistant'
  final String content;
  final DateTime timestamp;

  ChatMessageEntity({
    required this.serverIp,
    required this.profileId,
    required this.role,
    required this.content,
    required this.timestamp,
  });
}