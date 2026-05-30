import 'package:isar/isar.dart';

part 'chat_message_entity.g.dart';

@collection
class ChatMessageEntity {
  Id id = Isar.autoIncrement;

  late String serverIp; // Para filtrar mensajes por servidor
  late String profileId; // Para filtrar mensajes por perfil/usuario
  late String role; // 'user' o 'assistant'
  late String content;
  String? editedContent;
  late DateTime timestamp;

  ChatMessageEntity({
    required this.serverIp,
    required this.profileId,
    required this.role,
    required this.content,
    required this.timestamp,
  });
}