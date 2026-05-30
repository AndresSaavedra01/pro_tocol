
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:isar/isar.dart';
import 'package:pro_tocol/model/daos/AiConfigDAO.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';

class AiConfigRepository {
  static const String _tokenKey = 'ai_api_token';

  final AiConfigDAO _aiConfigDAO;
  final FlutterSecureStorage _secureStorage;

  AiConfigRepository(this._aiConfigDAO, this._secureStorage);

  Future<AiConfig?> getConfig() async {
    return await _aiConfigDAO.getConfig();
  }

  Future<void> saveConfig(AiConfig config) async {
    await _aiConfigDAO.saveConfig(config);
  }

  Future<void> deleteConfig(Id id) async {
    await _aiConfigDAO.deleteConfig(id);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }
}
