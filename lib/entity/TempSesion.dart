

import 'package:pro_tocol/entity/ShhConnection.dart';

class TempSession extends ShhConnection {
  final DateTime startedAt;
  final String connectionId; // Un ID único para identificar la pestaña abierta

  TempSession({
    required String ip,
    required String user,
    required String pass,
    required this.connectionId,
  }) : startedAt = DateTime.now(),
        super(ip, user, pass);
}