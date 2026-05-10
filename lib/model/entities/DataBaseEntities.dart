
import 'package:isar/isar.dart';
import 'package:pro_tocol/model/entities/GeneralConfig.dart';

part 'DataBaseEntities.g.dart';

@Collection()
class Profile {
  Id id = Isar.autoIncrement;

  late String profileName;

  final servers = IsarLinks<ServerConfig>();
}

@Collection()
class ServerConfig implements GeneralConfig {
  Id id = Isar.autoIncrement;

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

  @Backlink(to: 'servers')
  final profile = IsarLink<Profile>();
}

@Collection()
class AiConfig {
  Id id = Isar.autoIncrement;

  String provider;
  String host;
  int port;
  String model;

  AiConfig({
    this.provider = 'ollama',
    this.host = '127.0.0.1',
    this.port = 11434,
    this.model = '',
  });
}