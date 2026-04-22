
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basic_utils/basic_utils.dart';
import 'package:pro_tocol/model/entities/DataBaseEntities.dart';
import 'package:pro_tocol/model/services/SSHService.dart';

class SshKeyController {
  final FlutterSecureStorage _secureStorage;

  SshKeyController({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Genera llaves, las instala en el servidor y devuelve el ID para guardar en BD
  Future<String> generateAndInstallKey(ServerConfig config) async {
    if (config.password == null || config.password!.isEmpty) {
      throw Exception("Se requiere la contraseña para instalar la llave.");
    }

    // 1. Generar llaves
    final rsaKeyPair = CryptoUtils.generateRSAKeyPair();
    final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(rsaKeyPair.privateKey as RSAPrivateKey);
    final publicKeyOpenSsh = _encodeToOpenSshPublicKey(rsaKeyPair.publicKey as RSAPublicKey);

    // 2. Conectar temporalmente para instalar (usamos un servicio temporal para no ensuciar el Controller)
    final tempSshService = SSHService();
    try {
      await tempSshService.connect(config); // Aquí asume que usará el password

      final command = '''
        mkdir -p ~/.ssh && 
        chmod 700 ~/.ssh && 
        echo "$publicKeyOpenSsh" >> ~/.ssh/authorized_keys && 
        chmod 600 ~/.ssh/authorized_keys
      ''';

      final result = await tempSshService.runSingleCommand(command);
      if (result.toLowerCase().contains("error") || result.toLowerCase().contains("denied")) {
        throw Exception("Error instalando llave en servidor: $result");
      }
    } finally {
      tempSshService.disconnect();
    }

    // 3. Guardar en Secure Storage
    final keyId = 'ssh_key_${DateTime.now().millisecondsSinceEpoch}';
    await _secureStorage.write(key: keyId, value: privateKeyPem);

    return keyId;
  }

  /// Recupera la llave privada del almacenamiento seguro
  Future<String?> getPrivateKey(String keyId) async {
    return await _secureStorage.read(key: keyId);
  }

  /// Obtiene la llave pública en formato OpenSSH a partir del ID de la privada
  Future<String?> getPublicKey(String keyId) async {
    final privateKeyPem = await _secureStorage.read(key: keyId);
    if (privateKeyPem == null) return null;

    try {
      final privateKey = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);
      final publicKey = RSAPublicKey( privateKey.modulus!, privateKey.publicExponent!);
      return _encodeToOpenSshPublicKey(publicKey);
    } catch (e) {
      print("Error reconstruyendo pública: $e");
      return null;
    }
  }
  /// Elimina la llave (útil cuando se borra un servidor)
  Future<void> deleteKey(String keyId) async {
    await _secureStorage.delete(key: keyId);
  }

  /// Guarda una llave privada proporcionada manualmente por el usuario
  Future<String> saveManualKey(String privateKeyPem) async {
    if (privateKeyPem.isEmpty) throw Exception("La llave no puede estar vacía");

    // Generamos un ID único para esta llave manual
    final keyId = 'manual_key_${DateTime.now().millisecondsSinceEpoch}';
    await _secureStorage.write(key: keyId, value: privateKeyPem);
    return keyId;
  }

  // --- Helper Privado de Formateo (El que construimos antes) ---
  String _encodeToOpenSshPublicKey(RSAPublicKey publicKey) {
    final builder = BytesBuilder();
    void writeLength(int length) => builder.add([(length >> 24) & 0xFF, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF]);
    void writeBytes(List<int> bytes) { writeLength(bytes.length); builder.add(bytes); }
    void writeBigInt(BigInt value) {
      var hexString = value.toRadixString(16);
      if (hexString.length % 2 != 0) hexString = '0$hexString';
      var bytes = List<int>.generate(hexString.length ~/ 2, (i) => int.parse(hexString.substring(i * 2, i * 2 + 2), radix: 16));
      if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) bytes = [0x00, ...bytes];
      writeBytes(bytes);
    }

    writeBytes(utf8.encode('ssh-rsa'));
    writeBigInt(publicKey.exponent!);
    writeBigInt(publicKey.modulus!);

    final base64Key = base64.encode(builder.toBytes());
    return 'ssh-rsa $base64Key protocol_app';
  }
}