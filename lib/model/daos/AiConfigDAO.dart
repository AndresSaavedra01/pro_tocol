
import 'package:isar/isar.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';

class AiConfigDAO {
  final Isar isar;

  AiConfigDAO(this.isar);

  Future<AiConfig?> getConfig() async {
    return await isar.aiConfigs.where().findFirst();
  }

  Future<void> saveConfig(AiConfig config) async {
    await isar.writeTxn(() async {
      await isar.aiConfigs.put(config);
    });
  }

  Future<bool> deleteConfig(Id id) async {
    return await isar.writeTxn(() async {
      return await isar.aiConfigs.delete(id);
    });
  }
}
