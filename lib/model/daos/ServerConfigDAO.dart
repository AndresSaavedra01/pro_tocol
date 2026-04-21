
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

  // Buscar servidores por host (ejemplo de query personalizada)
  Future<List<ServerConfig>> findServersByHost(String host) async {
    return await isar.serverConfigs
        .filter()
        .hostContains(host, caseSensitive: false)
        .findAll();
  }

  // Obtener el perfil asociado a un servidor (vía Backlink)
  Future<Profile?> getParentProfile(ServerConfig config) async {
    await config.profile.load();
    return config.profile.value;
  }

  // Eliminar un servidor
  Future<bool> deleteServer(Id id) async {
    return await isar.writeTxn(() async {
      return await isar.serverConfigs.delete(id);
    });
  }
}