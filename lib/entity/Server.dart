
import 'package:pro_tocol/entity/ShhConnection.dart';

class server extends ShhConnection {

  String alias;
  server({
    required this.alias,
    required String user,
    required String ip,
    required String pass
  }) : super(ip, user, pass) {
    saveInDataBase();
  }

  void saveInDataBase() {
    print("Guardando $alias en la memoria local...");
  }

}

