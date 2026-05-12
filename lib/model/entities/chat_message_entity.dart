import 'package:isar/isar.dart';
part 'chat_message_entity.g.dart';

@collection
class ChatMessageEntity {
  Id id = Isar.autoIncrement;

  @Index()
  final String serverIp; 
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessageEntity({
    required this.serverIp,
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}