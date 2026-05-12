import 'package:isar/isar.dart';
import '../entities/chat_message_entity.dart';

class ChatHistoryRepository {
  final Isar isar;

  ChatHistoryRepository(this.isar);

  // Guardar un mensaje
  Future<void> saveMessage(ChatMessageEntity message) async {
    await isar.writeTxn(() async {
      await isar.chatMessageEntitys.put(message);
    });
  }

  // Cargar historial por IP
  Future<List<ChatMessageEntity>> getMessagesByServer(String ip) async {
    return await isar.chatMessageEntitys
        .filter()
        .serverIpEqualTo(ip)
        .sortByTimestamp()
        .findAll();
  }
}