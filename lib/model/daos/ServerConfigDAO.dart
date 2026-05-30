import 'package:isar/isar.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';

class ServerConfigDAO {
  final Isar isar;

  ServerConfigDAO(this.isar);

  // Guardar o actualizar configuración de servidor
  Future<void> saveServerConfig(ServerConfig config) async {
    await isar.writeTxn(() async {
      await isar.serverConfigs.put(config);
    });
  }

  Future<ServerConfig?> getServerConfigById(Id id) async {
    return await isar.serverConfigs.get(id);
  }

  // Buscar servidores por host
  Future<List<ServerConfig>> findServersByHost(String host) async {
    return await isar.serverConfigs
        .filter()
        .hostContains(host, caseSensitive: false)
        .findAll();
  }

  // Obtener todos los servidores de un perfil específico
  Future<List<ServerConfig>> getServersByProfileId(String profileId) async {
    return await isar.serverConfigs
        .filter()
        .profileIdEqualTo(profileId)
        .findAll();
  }

  // Eliminar un servidor
  Future<bool> deleteServer(Id id) async {
    return await isar.writeTxn(() async {
      return await isar.serverConfigs.delete(id);
    });
  }
}