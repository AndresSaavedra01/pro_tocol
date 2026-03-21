
import 'package:isar/isar.dart';
import 'Server.dart'; // Importa la clase hija

part 'Profile.g.dart';

@collection
class Profile {
  Id id = Isar.autoIncrement;

  late String name;
  late String avatarPath;

  // Relación: Un perfil tiene MUCHOS servidores
  final servers = IsarLinks<Server>();
}