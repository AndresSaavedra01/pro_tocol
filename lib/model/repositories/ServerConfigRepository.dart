
import 'package:isar/isar.dart';
import 'package:pro_tocol/model/daos/ServerConfigDAO.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';

class ServerConfigRepository {
  final ServerConfigDAO _serverDAO;

  // Estructura de datos: Map para búsqueda rápida por ID
  final Map<Id, ServerConfig> _serverMap = {};

  ServerConfigRepository(this._serverDAO);

  List<ServerConfig> get allConfigs => _serverMap.values.toList();

  // Sincronizar todos los servidores existentes
  Future<void> loadAll(List<ServerConfig> configs) async {
    _serverMap.clear();
    for (var config in configs) {
      _serverMap[config.id] = config;
    }
  }

  // Guardar en DB y actualizar el Map
  Future<void> updateConfig(ServerConfig config) async {
    await _serverDAO.saveServerConfig(config);
    _serverMap[config.id] = config;
  }

  // Eliminar de DB y Map
  Future<void> deleteConfig(Id id) async {
    final success = await _serverDAO.deleteServer(id);
    if (success) {
      _serverMap.remove(id);
    }
  }
}