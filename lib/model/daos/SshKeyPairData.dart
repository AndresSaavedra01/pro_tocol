import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:pro_tocol/model/entities/Server.dart';

class SshKeyPairData {
  final String privateKey;
  final String publicKey;
  SshKeyPairData({required this.privateKey, required this.publicKey});
}

class SshKeyManager {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// MÉTODO PRINCIPAL: Genera e instala las llaves usando el objeto Server
  Future<void> setupKeysForServer(Server server) async {
    final config = server.config;

    if (config.password == null || config.password!.isEmpty) {
      throw Exception("Se requiere la contraseña en ServerConfig para la instalación inicial.");
    }

    try {
      // 1. Generar el par de claves
      final keys = await _generateRsaKeyPair();

      // 2. Conectar usando el servicio que ya vive dentro de Server
      // Usamos el método connectWithPassword que definimos en SSHService anteriormente
      await server.sshService.connectWithPassword(config);

      // 3. Instalar la clave pública
      await _installPublicKey(server, keys.publicKey);

      // Desconectar tras la instalación
      server.sshService.disconnect();

      // 4. Guardar clave privada con un ID único
      final keyId = 'key_${config.id}_${DateTime.now().millisecondsSinceEpoch}';
      await _secureStorage.write(key: keyId, value: keys.privateKey);

      // 5. Actualizar la entidad interna
      config.keyPairId = keyId;
      // Opcional: config.password = null;

    } catch (e) {
      server.sshService.disconnect();
      rethrow;
    }
  }

  // --- Helpers Privados ---

  Future<SshKeyPairData> _generateRsaKeyPair() async {
    final rsaKeyPair = CryptoUtils.generateRSAKeyPair();
    final privateKey = CryptoUtils.encodeRSAPrivateKeyToPem(rsaKeyPair.privateKey as RSAPrivateKey);
    final publicKey = CryptoUtils.encodeRSAPublicKeyToPem(rsaKeyPair.publicKey as RSAPublicKey);

    return SshKeyPairData(
      privateKey: privateKey,
      publicKey: publicKey,
    );
  }

  Future<void> _installPublicKey(Server server, String pubKey) async {
    final command = '''
      mkdir -p ~/.ssh && 
      chmod 700 ~/.ssh && 
      echo "$pubKey" >> ~/.ssh/authorized_keys && 
      chmod 600 ~/.ssh/authorized_keys
    ''';

    // Usamos el método de ejecución del servicio del Server
    final result = await server.sshService.runSingleCommand(command);

    if (result.toLowerCase().contains("error") || result.toLowerCase().contains("denied")) {
      throw Exception("Error en servidor: $result");
    }
  }

  /// Recuperar la llave privada para el momento de la conexión
  Future<String?> getPrivateKey(String keyId) async {
    return await _secureStorage.read(key: keyId);
  }
}