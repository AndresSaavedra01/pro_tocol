import 'package:isar/isar.dart';
import 'package:pro_tocol/model/entities/GeneralConfig.dart';

part 'DataBaseEntities.g.dart';

@Collection()
class ServerConfig implements GeneralConfig {
  Id id = Isar.autoIncrement;

  late String profileId; // UID del usuario en Supabase

  @override
  late String host;
  @override
  late String username;
  @override
  late int port;
  @override
  String? password;
  @override
  String? keyPairId;
}

@Collection()
class AiConfig {
  Id id = Isar.autoIncrement;

  String provider;
  String host;
  int port;
  String model;
  String iaPersonality;

  AiConfig({
    this.provider = 'ollama',
    this.host = '127.0.0.1',
    this.port = 11434,
    this.model = '',
    this.iaPersonality = 'tatiana',
  });
}