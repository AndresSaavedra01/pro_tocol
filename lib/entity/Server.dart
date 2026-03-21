
import 'package:isar/isar.dart';

import 'ShhConnection.dart';

part 'Server.g.dart';

@collection
class Server extends ShhConnection {
  Id id = Isar.autoIncrement;
  String alias;

  Server({
    required this.alias,
    required String ip,
    required String user,
    required String pass,
  }) : super(ip, user, pass); // Pasamos los datos al padre
}

