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

  // Cargar historial por IP y Perfil
  Future<List<ChatMessageEntity>> getMessagesByServerAndProfile(String ip, String profileId) async {
    return await isar.chatMessageEntitys
        .filter()
        .serverIpEqualTo(ip)
        .and()
        .profileIdEqualTo(profileId)
        .sortByTimestamp()
        .findAll();
  }

  Future<void> deleteMessage(int id) async {
    await isar.writeTxn(() async {
      await isar.chatMessageEntitys.delete(id);
    });
  }

  Future<void> deleteAllByServerAndProfile(String ip, String profileId) async {
    await isar.writeTxn(() async {
      final messages = await isar.chatMessageEntitys
          .filter()
          .serverIpEqualTo(ip)
          .and()
          .profileIdEqualTo(profileId)
          .findAll();
      if (messages.isEmpty) return;
      final ids = messages.map((e) => e.id).toList();
      await isar.chatMessageEntitys.deleteAll(ids);
    });
  }

  Future<void> updateMessageContent(int id, String newContent) async {
    await isar.writeTxn(() async {
      final message = await isar.chatMessageEntitys.get(id);
      if (message == null) return;
      message.editedContent = newContent;
      await isar.chatMessageEntitys.put(message);
    });
  }
}