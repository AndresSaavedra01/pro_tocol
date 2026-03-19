import 'package:flutter/services.dart';

class SSHController {

  static const MethodChannel _channel = MethodChannel('ssh_channel');

  Future<String> ejecutarComando({
    required String ip,
    required String usuario,
    required String password,
    required String comando,
  }) async {

    // 🛑 Validaciones básicas
    if (ip.isEmpty || usuario.isEmpty || password.isEmpty || comando.isEmpty) {
      throw Exception("Todos los campos son obligatorios");
    }

    try {
      final result = await _channel.invokeMethod('executeSSH', {
        "ip": ip,
        "usuario": usuario,
        "password": password,
        "comando": comando,
      });

      return result.toString();

    } on PlatformException catch (e) {
      return "Error nativo: ${e.message}";
    } catch (e) {
      return "Error: $e";
    }
  }
}